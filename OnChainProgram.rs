#!/usr/bin/env rust

/**
 * MAGNUM OPUS // Solana On-Chain Program for Magnum Opus
 * High-performance, memory-safe on-chain program logic for the Magnum Opus platform.
 * Handles state management, transaction processing, and event emission on Solana.
 */
use anchor_lang::prelude::*;

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
}

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
    let fee = (amount as u128)
        .checked_mul(fee_basis_points as u128)
        .ok_or(MagnumError::MathOverflow)?
        .checked_div(10_000)
        .ok_or(MagnumError::MathOverflow)?;
    Ok(fee as u64)
}

fn current_timestamp() -> Result<i64> {
    Ok(Clock::get()?.unix_timestamp)
}

// -----------------------------------------------------------------------------
// Contexts
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
        init_if_needed,
        payer = sender,
        space = 8 + std::mem::size_of::<UserAccount>(),
        seeds = [b"user_account", sender.key().as_ref()],
        bump
    )]
    pub sender_account: Account<'info, UserAccount>,
    #[account(
        init_if_needed,
        payer = sender,
        space = 8 + std::mem::size_of::<UserAccount>(),
        seeds = [b"user_account", recipient.key().as_ref()],
        bump
    )]
    pub recipient_account: Account<'info, UserAccount>,
    #[account(
        init,
        payer = sender,
        space = 8 + std::mem::size_of::<TransactionRecord>(),
        seeds = [b"transaction_record", tx_id.as_ref()],
        bump
    )]
    pub transaction_record: Account<'info, TransactionRecord>,
    #[account(mut)]
    pub sender: Signer<'info>,
    /// CHECK: This is not dangerous because we don't read or write from this account
    pub recipient: AccountInfo<'info>,
    #[account(mut)]
    pub treasury: SystemAccount<'info>,
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
    #[account(mut)]
    pub treasury: SystemAccount<'info>,
    #[account(mut)]
    pub recipient: SystemAccount<'info>,
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
        has_one = owner
    )]
    pub user_account: Account<'info, UserAccount>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub recipient: SystemAccount<'info>,
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
// Program entry point
// -----------------------------------------------------------------------------
#[program]
pub mod magnum_opus {
    use super::*;

    /// Initialize the Magnum Opus program state
    pub fn initialize(
        ctx: Context<Initialize>,
        fee_basis_points: u16,
        reward_rate_per_sec: u64,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;

        state.bump = *ctx.bumps.get("state").unwrap();
        state.authority = authority.key();
        state.treasury = ctx.accounts.treasury.key();
        state.fee_basis_points = fee_basis_points;
        state.reward_rate_per_sec = reward_rate_per_sec;
        state.transaction_count = 0;
        state.total_volume = 0;
        state.proposal_count = 0;
        state.is_paused = false;
        state.accumulated_fees = 0;

        emit!(ProtocolInitializedEvent {
            authority: authority.key(),
            treasury: ctx.accounts.treasury.key(),
            fee_basis_points,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Update the program configuration
    pub fn update_config(
        ctx: Context<UpdateConfig>,
        fee_basis_points: Option<u16>,
        treasury: Option<Pubkey>,
        is_paused: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;

        if let Some(fee_basis_points) = fee_basis_points {
            if fee_basis_points > 10000 {
                return Err(MagnumError::InvalidFeeBasisPoints.into());
            }
            state.fee_basis_points = fee_basis_points;
        }

        if let Some(treasury) = treasury {
            state.treasury = treasury;
        }

        if let Some(is_paused) = is_paused {
            state.is_paused = is_paused;
        }

        emit!(ConfigUpdatedEvent {
            authority: authority.key(),
            fee_basis_points: state.fee_basis_points,
            treasury: state.treasury,
            is_paused: state.is_paused,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Process a transaction between two users
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
        let treasury = &ctx.accounts.treasury;

        // Check if the protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate the transaction amount
        if gross_amount == 0 {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Validate the memo length
        if memo.len() > 100 {
            return Err(MagnumError::InvalidMemoLength.into());
        }

        // Calculate the fee
        let fee_amount = calculate_fee(gross_amount, state.fee_basis_points)?;
        let net_amount = gross_amount.checked_sub(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Check if the sender has sufficient funds
        if sender_account.balance < gross_amount {
            return Err(MagnumError::InsufficientFunds.into());
        }

        // Update the sender's balance
        sender_account.balance = sender_account.balance.checked_sub(gross_amount).ok_or(MagnumError::MathOverflow)?;
        sender_account.last_updated = current_timestamp()?;

        // Update the recipient's balance
        recipient_account.balance = recipient_account.balance.checked_add(net_amount).ok_or(MagnumError::MathOverflow)?;
        recipient_account.last_updated = current_timestamp()?;

        // Update the treasury balance
        state.accumulated_fees = state.accumulated_fees.checked_add(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Update the transaction record
        transaction_record.tx_id = tx_id;
        transaction_record.sender = sender.key();
        transaction_record.recipient = recipient.key();
        transaction_record.gross_amount = gross_amount;
        transaction_record.fee_amount = fee_amount;
        transaction_record.net_amount = net_amount;
        transaction_record.memo = memo;
        transaction_record.timestamp = current_timestamp()?;
        transaction_record.bump = *ctx.bumps.get("transaction_record").unwrap();

        // Update the state
        state.transaction_count = state.transaction_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state.total_volume.checked_add(gross_amount).ok_or(MagnumError::MathOverflow)?;

        // Emit the transaction processed event
        emit!(TransactionProcessedEvent {
            sender: sender.key(),
            recipient: recipient.key(),
            gross_amount,
            fee_amount,
            net_amount,
            memo,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Withdraw accumulated fees to the treasury
    pub fn withdraw_fees(
        ctx: Context<WithdrawFees>,
        amount: u64,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;
        let treasury = &ctx.accounts.treasury;
        let recipient = &ctx.accounts.recipient;

        // Check if the amount is valid
        if amount == 0 || amount > state.accumulated_fees {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Transfer the funds
        let seeds = &[
            b"magnum_opus_state".as_ref(),
            &[state.bump],
        ];
        let signer = &[&seeds[..]];

        let ix = anchor_lang::solana_program::system_instruction::transfer(
            &treasury.key(),
            &recipient.key(),
            amount,
        );

        anchor_lang::solana_program::program::invoke_signed(
            &ix,
            &[
                treasury.to_account_info(),
                recipient.to_account_info(),
            ],
            signer,
        )?;

        // Update the state
        state.accumulated_fees = state.accumulated_fees.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;

        // Emit the fees withdrawn event
        emit!(FeesWithdrawnEvent {
            authority: authority.key(),
            amount,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Deposit funds into a user's account
    pub fn deposit(
        ctx: Context<Deposit>,
        amount: u64,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let user_account = &mut ctx.accounts.user_account;
        let user = &ctx.accounts.user;

        // Check if the protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate the amount
        if amount == 0 {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Update the user's balance
        user_account.balance = user_account.balance.checked_add(amount).ok_or(MagnumError::MathOverflow)?;
        user_account.last_updated = current_timestamp()?;

        // Emit the deposit event
        emit!(DepositEvent {
            user: user.key(),
            amount,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Withdraw funds from a user's account
    pub fn withdraw(
        ctx: Context<Withdraw>,
        amount: u64,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let user_account = &mut ctx.accounts.user_account;
        let user = &ctx.accounts.user;
        let recipient = &ctx.accounts.recipient;

        // Check if the protocol is paused
        if state.is_paused {
            return Err(MagnumError::ProtocolPaused.into());
        }

        // Validate the amount
        if amount == 0 || amount > user_account.balance {
            return Err(MagnumError::InvalidAmount.into());
        }

        // Update the user's balance
        user_account.balance = user_account.balance.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;
        user_account.last_updated = current_timestamp()?;

        // Transfer the funds
        let seeds = &[
            b"magnum_opus_state".as_ref(),
            &[state.bump],
        ];
        let signer = &[&seeds[..]];

        let ix = anchor_lang::solana_program::system_instruction::transfer(
            &user.key(),
            &recipient.key(),
            amount,
        );

        anchor_lang::solana_program::program::invoke_signed(
            &ix,
            &[
                user.to_account_info(),
                recipient.to_account_info(),
            ],
            signer,
        )?;

        // Emit the withdrawal event
        emit!(WithdrawalEvent {
            user: user.key(),
            amount,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }

    /// Update the reward rate for staking/yield
    pub fn update_reward_rate(
        ctx: Context<UpdateRewardRate>,
        new_reward_rate: u64,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = &ctx.accounts.authority;

        // Validate the new reward rate
        if new_reward_rate == 0 {
            return Err(MagnumError::InvalidRewardRate.into());
        }

        // Update the reward rate
        let old_reward_rate = state.reward_rate_per_sec;
        state.reward_rate_per_sec = new_reward_rate;

        // Emit the reward rate updated event
        emit!(RewardRateUpdatedEvent {
            authority: authority.key(),
            old_reward_rate,
            new_reward_rate,
            timestamp: current_timestamp()?,
        });

        Ok(())
    }
}