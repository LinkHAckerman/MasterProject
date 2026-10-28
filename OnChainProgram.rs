use anchor_lang::prelude::*;
use anchor_lang::solana_program::program::invoke;
use anchor_lang::solana_program::system_instruction;

declare_id!("MagnumOpus1111111111111111111111111111111111");

pub const REWARD_PRECISION: u128 = 1_000_000_000;
pub const FEE_DENOMINATOR: u64 = 10_000;

#[program]
pub mod on_chain_program {
    use super::*;

    // ---------------------------------------------------------------------
    // Vault Management
    // ---------------------------------------------------------------------
    /// Initialize a new vault for the given authority.
    /// The vault is a PDA seeded with "vault" and the bump.
    pub fn initialize(ctx: Context<Initialize>, bump: u8) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = *ctx.accounts.authority.key;
        vault.bump = bump;
        vault.balance = 0;
        vault.staked_balance = 0;
        vault.reward_debt = 0;
        vault.pending_rewards = 0;
        vault.reward_per_token_paid = 0;
        vault.created_at = Clock::get()?.unix_timestamp;
        vault.last_action_slot = Clock::get()?.slot;
        emit!(VaultInitialized { authority: vault.authority, bump });
        Ok(())
    }

    /// Deposit lamports into the vault.
    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let vault = &mut ctx.accounts.vault;
        vault.balance = vault
            .balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = Clock::get()?.slot;
        // Transfer lamports from the signer to the vault PDA.
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(DepositEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Withdraw lamports from the vault.
    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        vault.balance = vault
            .balance
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        vault.last_action_slot = Clock::get()?.slot;
        // Transfer lamports back to the authority.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(WithdrawEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Change the authority of the vault. Only the current authority can call.
    pub fn set_authority(ctx: Context<SetAuthority>, new_authority: Pubkey) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        let old = vault.authority;
        vault.authority = new_authority;
        emit!(AuthorityChanged { old_authority: old, new_authority });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Staking Pool Management
    // ---------------------------------------------------------------------
    /// Initialize a new global staking pool with reward emission rate per second.
    pub fn initialize_staking_pool(
        ctx: Context<InitializeStakingPool>,
        reward_rate_per_second: u64,
        bump: u8,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        pool.authority = ctx.accounts.authority.key();
        pool.bump = bump;
        pool.total_staked = 0;
        pool.reward_per_token = 0;
        pool.last_update_time = Clock::get()?.unix_timestamp;
        pool.reward_rate_per_second = reward_rate_per_second;
        pool.total_rewards_distributed = 0;
        pool.paused = false;
        emit!(StakingPoolInitialized {
            authority: pool.authority,
            reward_rate_per_second,
            timestamp: pool.last_update_time,
        });
        Ok(())
    }

    /// Pause the staking pool (emergency stop).
    pub fn pause_pool(ctx: Context<PausePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = true;
        emit!(PoolPaused { authority: pool.authority, timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    /// Resume a paused staking pool.
    pub fn resume_pool(ctx: Context<ResumePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = false;
        emit!(PoolResumed { authority: pool.authority, timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    /// Update the reward rate of the staking pool.
    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_rate: u64) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.reward_rate_per_second = new_rate;
        emit!(RewardRateUpdated {
            authority: pool.authority,
            new_rate,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Stake tokens into the pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update the reward per token.
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward_per_token = pool.reward_per_token
                .checked_add(
                    (time_elapsed as u128)
                        .checked_mul(pool.reward_rate_per_second as u128)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_mul(REWARD_PRECISION)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_div(pool.total_staked as u128)
                        .ok_or(ErrorCode::DivisionByZero)?,
                )
                .ok_or(ErrorCode::Overflow)?;
            pool.reward_per_token = reward_per_token;
            pool.last_update_time = current_time;
        }

        // Update the user's reward debt and pending rewards.
        let reward_debt = vault.reward_debt
            .checked_add(
                vault.staked_balance
                    .checked_mul(pool.reward_per_token)
                    .ok_or(ErrorCode::Overflow)?
                    .checked_div(REWARD_PRECISION)
                    .ok_or(ErrorCode::DivisionByZero)?
                    .checked_sub(vault.reward_debt)
                    .ok_or(ErrorCode::Underflow)?,
            )
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_debt = reward_debt;

        // Update the pool's total staked balance.
        pool.total_staked = pool
            .total_staked
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;

        // Update the vault's staked balance.
        vault.staked_balance = vault
            .staked_balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;

        // Transfer lamports from the vault to the pool.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(StakeEvent {
            authority: vault.authority,
            amount,
            new_staked_balance: vault.staked_balance,
            timestamp: current_time,
        });
        Ok(())
    }

    /// Unstake tokens from the pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientFunds);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update the reward per token.
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward_per_token = pool.reward_per_token
                .checked_add(
                    (time_elapsed as u128)
                        .checked_mul(pool.reward_rate_per_second as u128)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_mul(REWARD_PRECISION)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_div(pool.total_staked as u128)
                        .ok_or(ErrorCode::DivisionByZero)?,
                )
                .ok_or(ErrorCode::Overflow)?;
            pool.reward_per_token = reward_per_token;
            pool.last_update_time = current_time;
        }

        // Update the user's reward debt and pending rewards.
        let pending_rewards = vault.staked_balance
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionByZero)?
            .checked_sub(vault.reward_debt)
            .ok_or(ErrorCode::Underflow)?;
        vault.pending_rewards = pending_rewards;
        vault.reward_debt = 0;

        // Update the pool's total staked balance.
        pool.total_staked = pool
            .total_staked
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;

        // Update the vault's staked balance.
        vault.staked_balance = vault
            .staked_balance
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;

        // Transfer lamports from the pool to the vault.
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(UnstakeEvent {
            authority: vault.authority,
            amount,
            new_staked_balance: vault.staked_balance,
            pending_rewards,
            timestamp: current_time,
        });
        Ok(())
    }

    /// Claim pending rewards from the staking pool.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.pending_rewards > 0, ErrorCode::NoRewardsToClaim);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update the reward per token.
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward_per_token = pool.reward_per_token
                .checked_add(
                    (time_elapsed as u128)
                        .checked_mul(pool.reward_rate_per_second as u128)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_mul(REWARD_PRECISION)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_div(pool.total_staked as u128)
                        .ok_or(ErrorCode::DivisionByZero)?,
                )
                .ok_or(ErrorCode::Overflow)?;
            pool.reward_per_token = reward_per_token;
            pool.last_update_time = current_time;
        }

        // Update the user's reward debt and pending rewards.
        let pending_rewards = vault.staked_balance
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionByZero)?
            .checked_sub(vault.reward_debt)
            .ok_or(ErrorCode::Underflow)?;
        vault.pending_rewards = pending_rewards;
        vault.reward_debt = 0;

        // Transfer rewards from the pool to the vault.
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= pending_rewards;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += pending_rewards;

        emit!(RewardsClaimed {
            authority: vault.authority,
            amount: pending_rewards,
            timestamp: current_time,
        });
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<Vault>(),
        seeds = [b"vault", authority.key().as_ref()],
        bump,
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct InitializeStakingPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<StakingPool>(),
        seeds = [b"staking_pool"],
        bump,
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub reward_debt: u128,
    pub pending_rewards: u128,
    pub reward_per_token_paid: u128,
    pub created_at: i64,
    pub last_action_slot: u64,
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u128,
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u64,
    pub paused: bool,
}

#[event]
pub struct VaultInitialized {
    pub authority: Pubkey,
    pub bump: u8,
}

#[event]
pub struct DepositEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

#[event]
pub struct WithdrawEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

#[event]
pub struct AuthorityChanged {
    pub old_authority: Pubkey,
    pub new_authority: Pubkey,
}

#[event]
pub struct StakingPoolInitialized {
    pub authority: Pubkey,
    pub reward_rate_per_second: u64,
    pub timestamp: i64,
}

#[event]
pub struct PoolPaused {
    pub authority: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct PoolResumed {
    pub authority: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct RewardRateUpdated {
    pub authority: Pubkey,
    pub new_rate: u64,
    pub timestamp: i64,
}

#[event]
pub struct StakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_staked_balance: u64,
    pub timestamp: i64,
}

#[event]
pub struct UnstakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_staked_balance: u64,
    pub pending_rewards: u128,
    pub timestamp: i64,
}

#[event]
pub struct RewardsClaimed {
    pub authority: Pubkey,
    pub amount: u128,
    pub timestamp: i64,
}

#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount")]
    InvalidAmount,
    #[msg("Overflow")]
    Overflow,
    #[msg("Underflow")]
    Underflow,
    #[msg("Insufficient funds")]
    InsufficientFunds,
    #[msg("Unauthorized")]
    Unauthorized,
    #[msg("Division by zero")]
    DivisionByZero,
    #[msg("Pool is paused")]
    PoolPaused,
    #[msg("No rewards to claim")]
    NoRewardsToClaim,
}