#![allow(clippy::too_many_arguments)]
#!/usr/bin/env rust

/**
 * MAGNUM OPUS // Solana On-Chain Program for Magnum Opus
 * High-performance, memory-safe on-chain program logic for the Magnum Opus platform.
 * Handles state management, transaction processing, and event emission on Solana.
 */
use anchor_lang::prelude::*;
use anchor_lang::system_program::{transfer, Transfer};

// Unique identifier for this program
declare_id!("MagnumOpus1111111111111111111111111111111111");

// -----------------------------------------------------------------------------
// Error definitions
// -----------------------------------------------------------------------------
#[error_code]
pub enum MagnumError {
    /// Fee exceeds maximum allowed (1% of transaction amount)
    #[msg("Fee too high")]
    FeeTooHigh,
    /// Protocol is currently paused
    #[msg("Protocol is paused")]
    ProtocolPaused,
    /// Invalid transaction amount (must be positive)
    #[msg("Invalid amount")]
    InvalidAmount,
    /// Arithmetic overflow occurred
    #[msg("Math overflow")]
    MathOverflow,
    /// Operation was unauthorized (invalid account)
    #[msg("Unauthorized operation")]
    Unauthorized,
    /// Insufficient funds for transaction
    #[msg("Insufficient funds")]
    InsufficientFunds,
    /// Invalid memo length (must be <= 100 characters)
    #[msg("Invalid memo length")]
    InvalidMemoLength,
    /// Invalid reward rate (must be positive)
    #[msg("Invalid reward rate")]
    InvalidRewardRate,
    /// Invalid fee basis points (must be <= 10000)
    #[msg("Invalid fee basis points")]
    InvalidFeeBasisPoints,
    /// Invalid transaction signature
    #[msg("Invalid signature")]
    InvalidSignature,
    /// Transaction already processed
    #[msg("Transaction already processed")]
    TransactionAlreadyProcessed,
    /// Fee vault has insufficient balance
    #[msg("Fee vault insufficient balance")]
    FeeVaultInsufficientBalance,
}

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------
const MAX_MEMO_LENGTH: usize = 100;
const MAX_FEE_BASIS_POINTS: u16 = 10_000; // 100%
const FEE_VAULT_SEED: &[u8] = b"fee_vault";

// -----------------------------------------------------------------------------
// Account structures
// -----------------------------------------------------------------------------
#[account]
pub struct MagnumOpusState {
    /// Bump seed for PDA
    pub bump: u8,
    /// Authority account (program owner)
    pub authority: Pubkey,
    /// Treasury account (funds for program operations)
    pub treasury: Pubkey,
    /// Fee basis points (percentage of transaction amount, 1 bp = 0.01%)
    pub fee_basis_points: u16,
    /// Reward rate per second (for staking/yield)
    pub reward_rate_per_sec: u64,
    /// Transaction statistics
    pub transaction_count: u64,
    pub total_volume: u64,
    pub proposal_count: u64,
    /// Protocol state flags
    pub is_paused: bool,
    /// Accumulated fees collected (in lamports)
    pub accumulated_fees: u64,
}

#[account]
pub struct UserAccount {
    /// Owner of this account (wallet address)
    pub owner: Pubkey,
    /// Current balance (in lamports)
    pub balance: u64,
    /// Last updated timestamp (unix seconds)
    pub last_updated: i64,
    /// Bump seed for PDA
    pub bump: u8,
}

#[account]
pub struct TransactionRecord {
    /// Transaction ID (hash of the transaction)
    pub tx_id: [u8; 32],
    /// Sender's public key
    pub sender: Pubkey,
    /// Recipient's public key
    pub recipient: Pubkey,
    /// Gross amount (before fees)
    pub gross_amount: u64,
    /// Fee amount
    pub fee_amount: u64,
    /// Net amount (after fees)
    pub net_amount: u64,
    /// Memo associated with the transaction
    pub memo: String,
    /// Timestamp of the transaction
    pub timestamp: i64,
    /// Bump seed for PDA
    pub bump: u8,
}

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------
#[event]
pub struct ProtocolInitializedEvent {
    pub authority: Pubkey,
    pub treasury: Pubkey,
    pub fee_basis_points: u16,
    pub timestamp: i64,
}

#[event]
pub struct ConfigUpdatedEvent {
    pub authority: Pubkey,
    pub fee_basis_points: u16,
    pub treasury: Pubkey,
    pub is_paused: bool,
    pub timestamp: i64,
}

#[event]
pub struct TransactionProcessedEvent {
    pub sender: Pubkey,
    pub recipient: Pubkey,
    pub gross_amount: u64,
    pub fee_amount: u64,
    pub net_amount: u64,
    pub memo: String,
    pub timestamp: i64,
}

#[event]
pub struct FeesWithdrawnEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct DepositEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct WithdrawalEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct RewardRateUpdatedEvent {
    pub authority: Pubkey,
    pub old_reward_rate: u64,
    pub new_reward_rate: u64,
    pub timestamp: i64,
}

// -----------------------------------------------------------------------------
// Utility functions
// -----------------------------------------------------------------------------
pub fn calculate_fee(amount: u64, fee_basis_points: u16) -> Result<u64> {
    // fee = amount * fee_basis_points / 10_000
    let fee = (amount
        .checked_mul(fee_basis_points as u64)
        .ok_or(MagnumError::MathOverflow)?
        .checked_div(10_000)
        .ok_or(MagnumError::MathOverflow)?);
    Ok(fee)
}

fn validate_memo(memo: &str) -> Result<()> {
    if memo.len() > MAX_MEMO_LENGTH {
        return Err(MagnumError::InvalidMemoLength.into());
    }
    Ok(())
}

// -----------------------------------------------------------------------------
// Instruction handlers - Account validation structs
// -----------------------------------------------------------------------------
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<MagnumOpusState>(),
        seeds = [b"magnum_opus_state"],
        bump
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(
        init,
        payer = authority,
        space = 8,
        seeds = [FEE_VAULT_SEED],
        bump
    )]
    /// CHECK: Fee vault PDA - holds accumulated fees
    pub fee_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump,
        has_one = authority
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"user_account", sender.key().as_ref()],
        bump = sender_account.bump,
        has_one = owner @ MagnumError::Unauthorized
    )]
    pub sender_account: Account<'info, UserAccount>,
    #[account(
        mut,
        seeds = [b"user_account", recipient.key().as_ref()],
        bump = recipient_account.bump
    )]
    pub recipient_account: Account<'info, UserAccount>,
    #[account(
        init,
        payer = sender,
        space = 8 + std::mem::size_of::<TransactionRecord>() + MAX_MEMO_LENGTH,
        seeds = [b"transaction_record", &tx_id[..]],
        bump
    )]
    pub transaction_record: Account<'info, TransactionRecord>,
    #[account(mut)]
    pub sender: Signer<'info>,
    /// CHECK: Recipient system account for lamport transfer
    #[account(mut)]
    pub recipient: UncheckedAccount<'info>,
    #[account(
        mut,
        seeds = [FEE_VAULT_SEED],
        bump
    )]
    /// CHECK: Fee vault PDA
    pub fee_vault: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump,
        has_one = authority
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [FEE_VAULT_SEED],
        bump
    )]
    /// CHECK: Fee vault PDA
    pub fee_vault: UncheckedAccount<'info>,
    /// CHECK: Treasury account to receive withdrawn fees
    #[account(mut, address = state.treasury @ MagnumError::Unauthorized)]
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(
        init_if_needed,
        payer = user,
        space = 8 + std::mem::size_of::<UserAccount>(),
        seeds = [b"user_account", user.key().as_ref()],
        bump
    )]
    pub user_account: Account<'info, UserAccount>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"user_account", user.key().as_ref()],
        bump = user_account.bump,
        has_one = owner @ MagnumError::Unauthorized
    )]
    pub user_account: Account<'info, UserAccount>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = state.bump,
        has_one = authority
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

// -----------------------------------------------------------------------------
// Program module
// -----------------------------------------------------------------------------
#[program]
pub mod magnum_opus {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, fee_basis_points: u16) -> Result<()> {
        require!(
            fee_basis_points <= MAX_FEE_BASIS_POINTS,
            MagnumError::InvalidFeeBasisPoints
        );

        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;
        let clock = Clock::get()?;

        // Initialize state
        state.bump = *ctx.bumps.get("magnum_opus_state").unwrap();
        state.authority = authority.key();
        state.treasury = authority.key();
        state.fee_basis_points = fee_basis_points;
        state.reward_rate_per_sec = 0;
        state.transaction_count = 0;
        state.total_volume = 0;
        state.proposal_count = 0;
        state.is_paused = false;
        state.accumulated_fees = 0;

        emit!(ProtocolInitializedEvent {
            authority: authority.key(),
            treasury: authority.key(),
            fee_basis_points,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        fee_basis_points: Option<u16>,
        treasury: Option<Pubkey>,
        is_paused: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;
        let clock = Clock::get()?;

        if let Some(fp) = fee_basis_points {
            require!(fp <= MAX_FEE_BASIS_POINTS, MagnumError::InvalidFeeBasisPoints);
            state.fee_basis_points = fp;
        }
        if let Some(t) = treasury {
            state.treasury = t;
        }
        if let Some(p) = is_paused {
            state.is_paused = p;
        }

        emit!(ConfigUpdatedEvent {
            authority: authority.key(),
            fee_basis_points: state.fee_basis_points,
            treasury: state.treasury,
            is_paused: state.is_paused,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn process_transaction(
        ctx: Context<ProcessTransaction>,
        tx_id: [u8; 32],
        gross_amount: u64,
        memo: String,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let sender_account = &mut ctx.accounts.sender_account;
        let recipient_account = &mut ctx.accounts.recipient_account;
        let transaction_record = &mut ctx.accounts.transaction_record;
        let sender = &ctx.accounts.sender;
        let recipient = &ctx.accounts.recipient;
        let fee_vault = &ctx.accounts.fee_vault;
        let clock = Clock::get()?;

        // Check if protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate amount
        if gross_amount == 0 {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Validate memo
        validate_memo(&memo)?;

        // Calculate fee
        let fee_amount = calculate_fee(gross_amount, state.fee_basis_points)?;
        let net_amount = gross_amount.checked_sub(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Check sender has sufficient balance
        if sender_account.balance < gross_amount {
            return Err(MagnumError::InsufficientFunds.into());
        }

        // Update sender and recipient balances in UserAccount PDAs
        sender_account.balance = sender_account.balance.checked_sub(gross_amount).ok_or(MagnumError::MathOverflow)?;
        sender_account.last_updated = clock.unix_timestamp;

        recipient_account.balance = recipient_account.balance.checked_add(net_amount).ok_or(MagnumError::MathOverflow)?;
        recipient_account.last_updated = clock.unix_timestamp;

        // Transfer fee to fee vault from sender
        if fee_amount > 0 {
            let cpi_context = CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                Transfer {
                    from: sender.to_account_info(),
                    to: fee_vault.to_account_info(),
                },
            );
            transfer(cpi_context, fee_amount)?;
        }

        // Transfer net amount to recipient
        if net_amount > 0 {
            let cpi_context = CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                Transfer {
                    from: sender.to_account_info(),
                    to: recipient.to_account_info(),
                },
            );
            transfer(cpi_context, net_amount)?;
        }

        // Update state
        state.transaction_count = state.transaction_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state.total_volume.checked_add(gross_amount).ok_or(MagnumError::MathOverflow)?;
        state.accumulated_fees = state.accumulated_fees.checked_add(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Initialize transaction record
        transaction_record.tx_id = tx_id;
        transaction_record.sender = sender.key();
        transaction_record.recipient = recipient.key();
        transaction_record.gross_amount = gross_amount;
        transaction_record.fee_amount = fee_amount;
        transaction_record.net_amount = net_amount;
        transaction_record.memo = memo.clone();
        transaction_record.timestamp = clock.unix_timestamp;
        transaction_record.bump = *ctx.bumps.get("transaction_record").unwrap();

        // Emit event
        emit!(TransactionProcessedEvent {
            sender: sender.key(),
            recipient: recipient.key(),
            gross_amount,
            fee_amount,
            net_amount,
            memo,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn withdraw_fees(ctx: Context<WithdrawFees>, amount: u64) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let fee_vault = &ctx.accounts.fee_vault;
        let treasury = &ctx.accounts.treasury;
        let authority = &ctx.accounts.authority;
        let clock = Clock::get()?;

        // Check if amount is valid
        if amount == 0 || amount > state.accumulated_fees {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Verify fee vault has sufficient lamports
        let fee_vault_balance = fee_vault.lamports();
        if fee_vault_balance < amount {
            return Err(MagnumError::FeeVaultInsufficientBalance.into());
        }

        // Transfer fees from fee vault to treasury
        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            Transfer {
                from: fee_vault.to_account_info(),
                to: treasury.to_account_info(),
            },
        );
        transfer(cpi_context, amount)?;

        // Update state
        state.accumulated_fees = state.accumulated_fees.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;

        // Emit event
        emit!(FeesWithdrawnEvent {
            authority: authority.key(),
            amount,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let user_account = &mut ctx.accounts.user_account;
        let user = &ctx.accounts.user;
        let clock = Clock::get()?;

        // Check if protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate amount
        if amount == 0 {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Initialize user account if newly created
        if user_account.owner == Pubkey::default() {
            user_account.owner = user.key();
            user_account.balance = 0;
            user_account.last_updated = clock.unix_timestamp;
            user_account.bump = *ctx.bumps.get("user_account").unwrap();
        }

        // Transfer lamports from user to program (user_account PDA)
        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            Transfer {
                from: user.to_account_info(),
                to: user_account.to_account_info(),
            },
        );
        transfer(cpi_context, amount)?;

        // Update user account balance
        user_account.balance = user_account.balance.checked_add(amount).ok_or(MagnumError::MathOverflow)?;
        user_account.last_updated = clock.unix_timestamp;

        // Emit event
        emit!(DepositEvent {
            user: user.key(),
            amount,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        let state = &ctx.accounts.state;
        let user_account = &mut ctx.accounts.user_account;
        let user = &ctx.accounts.user;
        let clock = Clock::get()?;

        // Check if protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate amount
        if amount == 0 {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Check user has sufficient balance
        if user_account.balance < amount {
            return Err(MagnumError::InsufficientFunds.into());
        }

        // Transfer lamports from user_account PDA to user
        // Note: PDA signing requires seeds
        let user_key = user.key();
        let seeds = &[
            b"user_account",
            user_key.as_ref(),
            &[user_account.bump],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_context = CpiContext::new_with_signer(
            ctx.accounts.system_program.to_account_info(),
            Transfer {
                from: user_account.to_account_info(),
                to: user.to_account_info(),
            },
            signer_seeds,
        );
        transfer(cpi_context, amount)?;

        // Update user account balance
        user_account.balance = user_account.balance.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;
        user_account.last_updated = clock.unix_timestamp;

        // Emit event
        emit!(WithdrawalEvent {
            user: user.key(),
            amount,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_reward_rate: u64) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;
        let clock = Clock::get()?;

        // Validate reward rate
        if new_reward_rate == 0 {
            return Err(MagnumError::InvalidRewardRate.into());
        }

        let old_reward_rate = state.reward_rate_per_sec;
        state.reward_rate_per_sec = new_reward_rate;

        // Emit event
        emit!(RewardRateUpdatedEvent {
            authority: authority.key(),
            old_reward_rate,
            new_reward_rate,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }
}
