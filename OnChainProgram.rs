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
        let authority = ctx.accounts.authority.key();
        let treasury = ctx.accounts.treasury.key();
        let clock = Clock::get()?;

        state.bump = *ctx.bumps.get("state").unwrap();
        state.authority = authority;
        state.treasury = treasury;
        state.fee_basis_points = fee_basis_points;
        state.reward_rate_per_sec = reward_rate_per_sec;
        state.transaction_count = 0;
        state.total_volume = 0;
        state.proposal_count = 0;
        state.is_paused = false;
        state.accumulated_fees = 0;

        emit!(ProtocolInitializedEvent {
            authority,
            treasury,
            fee_basis_points,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Update the program configuration (fee, treasury, pause flag)
    pub fn update_config(
        ctx: Context<UpdateConfig>,
        new_fee_basis_points: Option<u16>,
        new_reward_rate_per_sec: Option<u64>,
        new_treasury: Option<Pubkey>,
        pause: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = ctx.accounts.authority.key();
        let clock = Clock::get()?;

        // Only the authority can call this
        require!(authority == state.authority, MagnumError::Unauthorized);

        if let Some(fee) = new_fee_basis_points {
            state.fee_basis_points = fee;
        }
        if let Some(rate) = new_reward_rate_per_sec {
            state.reward_rate_per_sec = rate;
        }
        if let Some(treasury) = new_treasury {
            state.treasury = treasury;
        }
        if let Some(p) = pause {
            state.is_paused = p;
        }

        emit!(ConfigUpdatedEvent {
            authority,
            fee_basis_points: state.fee_basis_points,
            treasury: state.treasury,
            is_paused: state.is_paused,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Process a simple token transfer between two user accounts, applying protocol fee.
    pub fn process_transaction(
        ctx: Context<ProcessTransaction>,
        amount: u64,
        memo: String,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let sender = &mut ctx.accounts.sender_account;
        let recipient = &mut ctx.accounts.recipient_account;
        let clock = Clock::get()?;

        // Ensure protocol is active
        require!(!state.is_paused, MagnumError::ProtocolPaused);
        // Basic validation
        require!(amount > 0, MagnumError::InvalidAmount);
        require!(memo.len() <= 100, MagnumError::InvalidMemoLength);
        // Verify sender owns the source account
        require!(sender.owner == ctx.accounts.sender.key(), MagnumError::Unauthorized);
        // Verify sufficient balance
        require!(sender.balance >= amount, MagnumError::InsufficientFunds);

        // Calculate fee
        let fee = calculate_fee(amount, state.fee_basis_points)?;
        // Enforce max fee of 1% (i.e., 100 basis points)
        require!(state.fee_basis_points <= 100, MagnumError::FeeTooHigh);
        let net_amount = amount.checked_sub(fee).ok_or(MagnumError::MathOverflow)?;

        // Update balances
        sender.balance = sender.balance.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;
        recipient.balance = recipient.balance.checked_add(net_amount).ok_or(MagnumError::MathOverflow)?;
        state.accumulated_fees = state.accumulated_fees.checked_add(fee).ok_or(MagnumError::MathOverflow)?;

        // Update statistics
        state.transaction_count = state.transaction_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state.total_volume.checked_add(amount).ok_or(MagnumError::MathOverflow)?;

        // Update timestamps
        let now = clock.unix_timestamp;
        sender.last_updated = now;
        recipient.last_updated = now;

        emit!(TransactionProcessedEvent {
            sender: sender.owner,
            recipient: recipient.owner,
            gross_amount: amount,
            fee_amount: fee,
            net_amount,
            memo,
            timestamp: now,
        });
        Ok(())
    }

    /// Withdraw accumulated protocol fees to the treasury account.
    pub fn withdraw_fees(ctx: Context<WithdrawFees>) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let treasury = &mut ctx.accounts.treasury_account;
        let authority = ctx.accounts.authority.key();
        let clock = Clock::get()?;

        require!(authority == state.authority, MagnumError::Unauthorized);
        let amount = state.accumulated_fees;
        require!(amount > 0, MagnumError::InvalidAmount);

        // Transfer fees to treasury (simple balance addition for demo purposes)
        treasury.balance = treasury.balance.checked_add(amount).ok_or(MagnumError::MathOverflow)?;
        state.accumulated_fees = 0;

        emit!(FeesWithdrawnEvent {
            authority,
            amount,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Deposit lamports into a user account.
    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let user = &mut ctx.accounts.user_account;
        let clock = Clock::get()?;
        require!(amount > 0, MagnumError::InvalidAmount);
        // In a real program, lamports would be transferred via system_program::transfer.
        // Here we simply increase the stored balance for illustration.
        user.balance = user.balance.checked_add(amount).ok_or(MagnumError::MathOverflow)?;
        user.last_updated = clock.unix_timestamp;
        emit!(DepositEvent {
            user: user.owner,
            amount,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Withdraw lamports from a user account.
    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        let user = &mut ctx.accounts.user_account;
        let clock = Clock::get()?;
        require!(amount > 0, MagnumError::InvalidAmount);
        require!(user.balance >= amount, MagnumError::InsufficientFunds);
        user.balance = user.balance.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;
        user.last_updated = clock.unix_timestamp;
        emit!(WithdrawalEvent {
            user: user.owner,
            amount,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }
}

// -----------------------------------------------------------------------------
// Context structs for each instruction
// -----------------------------------------------------------------------------
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + std::mem::size_of::<MagnumOpusState>())]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: Treasury can be any account; we only store its Pubkey.
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    #[account(mut, has_one = authority)]
    pub state: Account<'info, MagnumOpusState>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(mut, has_one = authority)]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut, has_one = owner @ MagnumError::Unauthorized)]
    pub sender_account: Account<'info, UserAccount>,
    #[account(mut, has_one = owner @ MagnumError::Unauthorized)]
    pub recipient_account: Account<'info, UserAccount>,
    /// CHECK: Sender is a signer, not a program account.
    pub sender: Signer<'info>,
    pub authority: Signer<'info>, // Needed for fee withdrawal checks; can be same as sender.
}

#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    #[account(mut, has_one = authority)]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub treasury_account: Account<'info, UserAccount>, // Simplified treasury representation.
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, has_one = owner @ MagnumError::Unauthorized)]
    pub user_account: Account<'info, UserAccount>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, has_one = owner @ MagnumError::Unauthorized)]
    pub user_account: Account<'info, UserAccount>,
    pub owner: Signer<'info>,
}
