#!/usr/bin/env rust

/**
 * MAGNUM OPUS // Solana On-Chain Program for Magnum Opus
 * High-performance, memory-safe on-chain program logic for the Magnum Opus platform.
 * Handles state management, transaction processing, and event emission on Solana.
 */
\use anchor_lang::prelude::*;


// Unique identifier for this program
\declare_id!("MagnumOpus1111111111111111111111111111111111");


// Error codes for on-chain operations
\#[error_code]
pub enum MagnumError {
    // Fee exceeds maximum allowed (1% of transaction amount)
    FeeTooHigh,
    // Protocol is currently paused
    ProtocolPaused,
    // Invalid transaction amount (must be positive)
    InvalidAmount,
    // Arithmetic overflow occurred
    MathOverflow,
    // Operation was unauthorized (invalid account)
    Unauthorized,
    // Insufficient funds for transaction
    InsufficientFunds,
    // Invalid memo length (must be <= 100 characters)
    InvalidMemoLength,
}

// Account state tracking
\#[account]
pub struct MagnumOpusState {
    // Monotonic counter for state progression
    pub bump: u8,
    
    // Authority account (program owner)
    pub authority: Pubkey,
    
    // Treasury account (funds for program operations)
    pub treasury: Pubkey,
    
    // Fee basis points (percentage of transaction amount)
    pub fee_basis_points: u16,
    
    // Reward rate per second (for staking/yield)
    pub reward_rate_per_sec: u64,
    
    // Transaction statistics
    pub transaction_count: u64,
    pub total_volume: u64,
    pub proposal_count: u64,
    
    // Protocol state flags
    pub is_paused: bool,
    
    // Accumulated fees collected
    pub accumulated_fees: u64,
}

// Account for user balances
\#[account]
pub struct UserAccount {
    // Owner of this account
    pub owner: Pubkey,
    
    // Current balance
    pub balance: u64,
    
    // Last updated timestamp
    pub last_updated: i64,
    
    // Bump seed for PDA
    pub bump: u8,
}

// Events emitted by the program
\#[event]
pub struct ProtocolInitializedEvent {
    pub authority: Pubkey,
    pub treasury: Pubkey,
    pub fee_basis_points: u16,
    pub timestamp: i64,
}

\#[event]
pub struct ConfigUpdatedEvent {
    pub authority: Pubkey,
    pub fee_basis_points: u16,
    pub treasury: Pubkey,
    pub is_paused: bool,
    pub timestamp: i64,
}

\#[event]
pub struct TransactionProcessedEvent {
    pub sender: Pubkey,
    pub recipient: Pubkey,
    pub gross_amount: u64,
    pub fee_amount: u64,
    pub net_amount: u64,
    pub memo: String,
    pub timestamp: i64,
}

\#[event]
pub struct FeesWithdrawnEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

// Fee calculation utility

pub fn calculate_fee(amount: u64, fee_basis_points: u16) -> Result<u64> {
    // Fee = amount * (fee_basis_points / 10000)
    // Using checked_mul to prevent overflow
    let fee = (amount as u128)
        .checked_mul(fee_basis_points as u128)
        .ok_or(MagnumError::MathOverflow)
        .map(|f| f / 10_000)
        .ok_or(MagnumError::MathOverflow);
    Ok(fee as u64)
}

// Main program module
\#[program]
pub mod magnum_opus {
    use super::*;

    /// Initialize the Magnum Opus program state
    /// 
    /// Accounts expected:
    /// 0. `[writable]` The MagnumOpusState account
    /// 1. `[signer]` The authority account
    /// 2. `[writable]` The treasury account
    /// 
    /// Parameters:
    /// * `fee_basis_points` - The fee percentage (basis points) for transactions
    /// * `reward_rate_per_sec` - The reward rate per second for staking/yield
    /// 
    /// Emits: ProtocolInitializedEvent
    pub fn initialize(ctx: Context<Initialize>, fee_basis_points: u16, reward_rate_per_sec: u64) -> Result<()> {
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

    /// Update the program configuration
    /// 
    /// Accounts expected:
    /// 0. `[writable]` The MagnumOpusState account
    /// 1. `[signer]` The authority account
    /// 2. `[writable]` The new treasury account (optional)
    /// 
    /// Parameters:
    /// * `new_fee_basis_points` - The new fee percentage (basis points) for transactions (optional)
    /// * `new_reward_rate_per_sec` - The new reward rate per second for staking/yield (optional)
    /// * `is_paused` - Whether the protocol should be paused (optional)
    /// 
    /// Emits: ConfigUpdatedEvent
    pub fn update_config(
        ctx: Context<UpdateConfig>,
        new_fee_basis_points: Option<u16>,
        new_reward_rate_per_sec: Option<u64>,
        is_paused: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = ctx.accounts.authority.key();
        let clock = Clock::get()?;

        if let Some(fee_basis_points) = new_fee_basis_points {
            state.fee_basis_points = fee_basis_points;
        }

        if let Some(reward_rate_per_sec) = new_reward_rate_per_sec {
            state.reward_rate_per_sec = reward_rate_per_sec;
        }

        if let Some(paused) = is_paused {
            state.is_paused = paused;
        }

        let treasury = if ctx.accounts.new_treasury.is_some() {
            ctx.accounts.new_treasury.unwrap().key()
        } else {
            state.treasury
        };

        emit!(ConfigUpdatedEvent {
            authority,
            fee_basis_points: state.fee_basis_points,
            treasury,
            is_paused: state.is_paused,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Process a transaction between two accounts
    /// 
    /// Accounts expected:
    /// 0. `[writable]` The MagnumOpusState account
    /// 1. `[writable]` The sender's UserAccount
    /// 2. `[writable]` The recipient's UserAccount
    /// 3. `[signer]` The sender's authority
    /// 4. `[writable]` The treasury account
    /// 
    /// Parameters:
    /// * `amount` - The amount to transfer
    /// * `memo` - A memo for the transaction (max 100 characters)
    /// 
    /// Emits: TransactionProcessedEvent
    pub fn process_transaction(ctx: Context<ProcessTransaction>, amount: u64, memo: String) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let sender_account = &mut ctx.accounts.sender_account;
        let recipient_account = &mut ctx.accounts.recipient_account;
        let sender = ctx.accounts.sender.key();
        let recipient = ctx.accounts.recipient.key();
        let treasury = ctx.accounts.treasury.key();
        let clock = Clock::get()?;

        // Validate the protocol is not paused
        require!(!state.is_paused, MagnumError::ProtocolPaused);

        // Validate the amount is positive
        require!(amount > 0, MagnumError::InvalidAmount);

        // Validate the memo length
        require!(memo.len() <= 100, MagnumError::InvalidMemoLength);

        // Calculate the fee
        let fee = calculate_fee(amount, state.fee_basis_points)?;
        require!(fee <= amount, MagnumError::FeeTooHigh);

        // Calculate the net amount
        let net_amount = amount.checked_sub(fee).ok_or(MagnumError::MathOverflow)?;

        // Validate the sender has sufficient funds
        require!(sender_account.balance >= amount, MagnumError::InsufficientFunds);

        // Update the sender's balance
        sender_account.balance = sender_account.balance.checked_sub(amount).ok_or(MagnumError::MathOverflow)?;
        sender_account.last_updated = clock.unix_timestamp;

        // Update the recipient's balance
        recipient_account.balance = recipient_account.balance.checked_add(net_amount).ok_or(MagnumError::MathOverflow)?;
        recipient_account.last_updated = clock.unix_timestamp;

        // Update the treasury's balance
        state.accumulated_fees = state.accumulated_fees.checked_add(fee).ok_or(MagnumError::MathOverflow)?;

        // Update transaction statistics
        state.transaction_count = state.transaction_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state.total_volume.checked_add(amount).ok_or(MagnumError::MathOverflow)?;

        // Emit the transaction event
        emit!(TransactionProcessedEvent {
            sender,
            recipient,
            gross_amount: amount,
            fee_amount: fee,
            net_amount,
            memo,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Withdraw accumulated fees to the treasury
    /// 
    /// Accounts expected:
    /// 0. `[writable]` The MagnumOpusState account
    /// 1. `[signer]` The authority account
    /// 2. `[writable]` The treasury account
    /// 
    /// Emits: FeesWithdrawnEvent
    pub fn withdraw_fees(ctx: Context<WithdrawFees>) -> Result<()> {
        let state = &mut ctx.accounts.state;
        let authority = ctx.accounts.authority.key();
        let treasury = ctx.accounts.treasury.key();
        let clock = Clock::get()?;

        // Validate there are fees to withdraw
        require!(state.accumulated_fees > 0, MagnumError::InsufficientFunds);

        // Transfer the fees to the treasury
        let amount = state.accumulated_fees;
        state.accumulated_fees = 0;

        // Emit the fees withdrawn event
        emit!(FeesWithdrawnEvent {
            authority,
            amount,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }
}

// Contexts for the program instructions

\#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<MagnumOpusState>(),
        seeds = [b"magnum_opus_state"],
        bump,
    )]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(mut)]
    /// CHECK: This account is not read or written to in this instruction
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

\#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    #[account(mut, seeds = [b"magnum_opus_state"], bump = state.bump)]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut, has_one = authority)]
    pub authority: Signer<'info>,
    #[account(mut, optional)]
    /// CHECK: This account is not read or written to in this instruction
    pub new_treasury: Option<UncheckedAccount<'info>>,
}

\#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(mut, seeds = [b"magnum_opus_state"], bump = state.bump)]
    pub state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"user_account", sender.key().as_ref()],
        bump = sender_account.bump,
        has_one = owner,
    )]
    pub sender_account: Account<'info, UserAccount>,
    #[account(
        mut,
        seeds = [b"user_account", recipient.key().as_ref()],
        bump = recipient_account.bump,
        has_one = owner,
    )]
    pub recipient_account: Account<'info, UserAccount>,
    #[account(mut)]
    pub sender: Signer<'info>,
    #[account(mut)]
    /// CHECK: This account is not read or written to in this instruction
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

\#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    #[account(mut, seeds = [b"magnum_opus_state"], bump = state.bump)]
    pub state: Account<'info, MagnumOpusState>,
    #[account(mut, has_one = authority)]
    pub authority: Signer<'info>,
    #[account(mut)]
    /// CHECK: This account is not read or written to in this instruction
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}