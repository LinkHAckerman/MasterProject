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

    /// Stake lamports into the global pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        require!(amount > 0, ErrorCode::InvalidAmount);
        // Update global pool reward state first.
        update_pool(&mut ctx.accounts.staking_pool)?;
        // Transfer lamports from user to vault PDA.
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += amount;
        // Update vault balances.
        let vault = &mut ctx.accounts.vault;
        vault.balance = vault.balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        // Update user stake info.
        let user_info = &mut ctx.accounts.user_stake_info;
        // Accumulate pending rewards before changing stake.
        let pending = pending_rewards(user_info, &ctx.accounts.staking_pool)?;
        user_info.pending_rewards = user_info.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        user_info.amount = user_info.amount.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        user_info.reward_debt = (user_info.amount as u128)
            .checked_mul(ctx.accounts.staking_pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?;
        // Update pool totals.
        ctx.accounts.staking_pool.total_staked = ctx.accounts.staking_pool.total_staked.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        emit!(Staked { user: *ctx.accounts.user.key, amount, total_staked: ctx.accounts.staking_pool.total_staked });
        Ok(())
    }

    /// Unstake lamports from the global pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        let user_info = &mut ctx.accounts.user_stake_info;
        require!(user_info.amount >= amount, ErrorCode::InsufficientStaked);
        // Update global pool reward state.
        update_pool(&mut ctx.accounts.staking_pool)?;
        // Compute pending rewards and update user info.
        let pending = pending_rewards(user_info, &ctx.accounts.staking_pool)?;
        user_info.pending_rewards = user_info.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        user_info.amount = user_info.amount.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        user_info.reward_debt = (user_info.amount as u128)
            .checked_mul(ctx.accounts.staking_pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?;
        // Transfer lamports back to user.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? += amount;
        // Update vault balances.
        let vault = &mut ctx.accounts.vault;
        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        // Update pool totals.
        ctx.accounts.staking_pool.total_staked = ctx.accounts.staking_pool.total_staked.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        emit!(Unstaked { user: *ctx.accounts.user.key, amount, total_staked: ctx.accounts.staking_pool.total_staked });
        Ok(())
    }

    /// Claim pending rewards for a user.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        // Update pool to latest state.
        update_pool(&mut ctx.accounts.staking_pool)?;
        let user_info = &mut ctx.accounts.user_stake_info;
        // Calculate total pending rewards.
        let pending = pending_rewards(user_info, &ctx.accounts.staking_pool)?;
        let total = user_info.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        require!(total > 0, ErrorCode::NoRewardsAvailable);
        // Reset pending rewards.
        user_info.pending_rewards = 0;
        user_info.reward_debt = (user_info.amount as u128)
            .checked_mul(ctx.accounts.staking_pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?;
        // Transfer reward lamports from vault to user.
        let reward_lamports = total as u64; // Assuming reward fits in u64 for demo.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= reward_lamports;
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? += reward_lamports;
        emit!(RewardsClaimed { user: *ctx.accounts.user.key, amount: reward_lamports });
        Ok(())
    }
}

// ---------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------
fn update_pool(pool: &mut Account<StakingPool>) -> Result<()> {
    let now = Clock::get()?.unix_timestamp;
    if now <= pool.last_update_time {
        return Ok(());
    }
    if pool.total_staked == 0 {
        pool.last_update_time = now;
        return Ok(());
    }
    let elapsed = (now - pool.last_update_time) as u64;
    let reward = (elapsed as u128)
        .checked_mul(pool.reward_rate_per_second as u128)
        .ok_or(ErrorCode::Overflow)?;
    // reward_per_token = reward_per_token + (reward * REWARD_PRECISION) / total_staked
    let added_rpt = reward
        .checked_mul(REWARD_PRECISION)
        .ok_or(ErrorCode::Overflow)?
        .checked_div(pool.total_staked as u128)
        .ok_or(ErrorCode::DivisionByZero)?;
    pool.reward_per_token = pool.reward_per_token.checked_add(added_rpt).ok_or(ErrorCode::Overflow)?;
    pool.last_update_time = now;
    pool.total_rewards_distributed = pool.total_rewards_distributed.checked_add(reward as u64).ok_or(ErrorCode::Overflow)?;
    emit!(PoolUpdated { new_reward_per_token: pool.reward_per_token, timestamp: now });
    Ok(())
}

fn pending_rewards(user: &Account<UserStakeInfo>, pool: &Account<StakingPool>) -> Result<u128> {
    let accrued = (user.amount as u128)
        .checked_mul(pool.reward_per_token)
        .ok_or(ErrorCode::Overflow)?;
    let pending = accrued
        .checked_sub(user.reward_debt)
        .ok_or(ErrorCode::Underflow)?;
    Ok(pending / REWARD_PRECISION)
}

// ---------------------------------------------------------------------
// Account Definitions
// ---------------------------------------------------------------------
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

#[account]
pub struct UserStakeInfo {
    pub user: Pubkey,
    pub amount: u64,
    pub reward_debt: u128,
    pub pending_rewards: u128,
}

// ---------------------------------------------------------------------
// Context Definitions
// ---------------------------------------------------------------------
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + 32 + 1 + 8 + 8 + 16 + 16 + 16 + 8 + 8)]
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
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct InitializeStakingPool<'info> {
    #[account(init, payer = authority, space = 8 + 32 + 1 + 8 + 16 + 8 + 8 + 1)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(init_if_needed, payer = user, space = 8 + 32 + 8 + 16 + 16, seeds = [b"stake", user.key().as_ref()], bump)]
    pub user_stake_info: Account<'info, UserStakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, seeds = [b"stake", user.key().as_ref()], bump)]
    pub user_stake_info: Account<'info, UserStakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, seeds = [b"stake", user.key().as_ref()], bump)]
    pub user_stake_info: Account<'info, UserStakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
}

// ---------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------
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
pub struct Staked {
    pub user: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
}

#[event]
pub struct Unstaked {
    pub user: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
}

#[event]
pub struct RewardsClaimed {
    pub user: Pubkey,
    pub amount: u64,
}

#[event]
pub struct PoolUpdated {
    pub new_reward_per_token: u128,
    pub timestamp: i64,
}

// ---------------------------------------------------------------------
// Error Codes
// ---------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount supplied.")]
    InvalidAmount,
    #[msg("Overflow occurred during arithmetic operation.")]
    Overflow,
    #[msg("Underflow occurred during arithmetic operation.")]
    Underflow,
    #[msg("Division by zero.")]
    DivisionByZero,
    #[msg("Insufficient funds in vault.")]
    InsufficientFunds,
    #[msg("Unauthorized operation.")]
    Unauthorized,
    #[msg("Staking pool is currently paused.")]
    PoolPaused,
    #[msg("User does not have enough staked balance.")]
    InsufficientStaked,
    #[msg("No rewards available to claim.")]
    NoRewardsAvailable,
}
