use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;
use anchor_lang::solana_program::program::invoke;

declare_id!("MagnumOpus1111111111111111111111111111111111");

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------
pub const REWARD_PRECISION: u128 = 1_000_000_000; // 1e9 precision for reward calculations
pub const FEE_DENOMINATOR: u64 = 10_000; // basis points denominator (0.01% = 1)
pub const MAX_NAME_LEN: usize = 32;
pub const MAX_DESC_LEN: usize = 64;

// -----------------------------------------------------------------------------
// Program entry point
// -----------------------------------------------------------------------------
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

    /// Stake vault tokens into the global pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        require!(amount > 0, ErrorCode::InvalidAmount);
        // Update pool reward state first
        update_pool_rewards(&mut ctx.accounts.staking_pool)?;
        // Update user vault state
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        // Transfer from vault balance to staked balance
        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        // Update reward debt for the user
        vault.reward_debt = vault
            .reward_debt
            .checked_add((amount as u128)
                .checked_mul(ctx.accounts.staking_pool.reward_per_token as u128)
                .ok_or(ErrorCode::Overflow)?)
            .ok_or(ErrorCode::Overflow)?;
        // Update pool totals
        ctx.accounts.staking_pool.total_staked = ctx.accounts.staking_pool.total_staked.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        emit!(Staked { authority: vault.authority, amount, new_total_staked: ctx.accounts.staking_pool.total_staked });
        Ok(())
    }

    /// Unstake tokens and claim pending rewards.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        require!(amount > 0, ErrorCode::InvalidAmount);
        // Update pool rewards first
        update_pool_rewards(&mut ctx.accounts.staking_pool)?;
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientStaked);
        // Calculate pending rewards for the user before changing stake
        let pending = calculate_user_pending(vault, &ctx.accounts.staking_pool)?;
        vault.pending_rewards = vault.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        // Update balances
        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.balance = vault.balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        // Update reward debt
        vault.reward_debt = vault
            .reward_debt
            .checked_sub((amount as u128)
                .checked_mul(ctx.accounts.staking_pool.reward_per_token as u128)
                .ok_or(ErrorCode::Overflow)?)
            .ok_or(ErrorCode::Underflow)?;
        // Update pool totals
        ctx.accounts.staking_pool.total_staked = ctx.accounts.staking_pool.total_staked.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        emit!(Unstaked { authority: vault.authority, amount, new_total_staked: ctx.accounts.staking_pool.total_staked });
        Ok(())
    }

    /// Claim accumulated rewards for the caller's vault.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        require!(!ctx.accounts.staking_pool.paused, ErrorCode::PoolPaused);
        // Update pool rewards first
        update_pool_rewards(&mut ctx.accounts.staking_pool)?;
        let vault = &mut ctx.accounts.vault;
        // Compute total pending rewards
        let pending = calculate_user_pending(vault, &ctx.accounts.staking_pool)?;
        let total = vault.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        require!(total > 0, ErrorCode::NoRewards);
        // Reset pending rewards and reward debt
        vault.pending_rewards = 0;
        vault.reward_debt = (vault.staked_balance as u128)
            .checked_mul(ctx.accounts.staking_pool.reward_per_token as u128)
            .ok_or(ErrorCode::Overflow)?;
        // Transfer rewards (simulated as lamports for demo purposes)
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= total as u64;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += total as u64;
        ctx.accounts.staking_pool.total_rewards_distributed = ctx.accounts.staking_pool.total_rewards_distributed.checked_add(total as u64).ok_or(ErrorCode::Overflow)?;
        emit!(RewardsClaimed { authority: vault.authority, amount: total });
        Ok(())
    }
}

// -----------------------------------------------------------------------------
// Helper functions
// -----------------------------------------------------------------------------
fn update_pool_rewards(pool: &mut Account<StakingPool>) -> Result<()> {
    let now = Clock::get()?.unix_timestamp;
    if now <= pool.last_update_time {
        return Ok(());
    }
    if pool.total_staked == 0 {
        pool.last_update_time = now;
        return Ok(());
    }
    let elapsed = (now - pool.last_update_time) as u64;
    // reward_per_token is stored as a fixed point number with REWARD_PRECISION precision
    let reward = (elapsed as u128)
        .checked_mul(pool.reward_rate_per_second as u128)
        .ok_or(ErrorCode::Overflow)?
        .checked_mul(REWARD_PRECISION)
        .ok_or(ErrorCode::Overflow)?
        .checked_div(pool.total_staked as u128)
        .ok_or(ErrorCode::DivisionByZero)?;
    pool.reward_per_token = pool.reward_per_token.checked_add(reward as u64).ok_or(ErrorCode::Overflow)?;
    pool.last_update_time = now;
    Ok(())
}

fn calculate_user_pending(vault: &Vault, pool: &StakingPool) -> Result<u128> {
    let accrued = (vault.staked_balance as u128)
        .checked_mul(pool.reward_per_token as u128)
        .ok_or(ErrorCode::Overflow)?;
    let pending = accrued
        .checked_sub(vault.reward_debt)
        .ok_or(ErrorCode::Underflow)?;
    // Adjust back from fixed point precision
    Ok(pending / REWARD_PRECISION)
}

// -----------------------------------------------------------------------------
// Account structs
// -----------------------------------------------------------------------------
#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,               // Free lamports in the vault
    pub staked_balance: u64,        // Amount currently staked in the pool
    pub reward_debt: u128,          // Fixed‑point reward debt for accurate accounting
    pub pending_rewards: u64,       // Rewards accrued but not yet claimed
    pub reward_per_token_paid: u64, // Last known reward per token for this vault
    pub created_at: i64,
    pub last_action_slot: u64,
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u64, // Fixed‑point with REWARD_PRECISION
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u64,
    pub paused: bool,
}

// -----------------------------------------------------------------------------
// Context structs (instruction accounts)
// -----------------------------------------------------------------------------
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + std::mem::size_of::<Vault>())]
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
    #[account(init, payer = authority, space = 8 + std::mem::size_of::<StakingPool>())]
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
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------
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
    pub authority: Pubkey,
    pub amount: u64,
    pub new_total_staked: u64,
}

#[event]
pub struct Unstaked {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_total_staked: u64,
}

#[event]
pub struct RewardsClaimed {
    pub authority: Pubkey,
    pub amount: u128,
}

// -----------------------------------------------------------------------------
// Error codes
// -----------------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount supplied (must be > 0).")]
    InvalidAmount,
    #[msg("Arithmetic overflow occurred.")]
    Overflow,
    #[msg("Arithmetic underflow occurred.")]
    Underflow,
    #[msg("Division by zero.")]
    DivisionByZero,
    #[msg("Insufficient funds in vault.")]
    InsufficientFunds,
    #[msg("Unauthorized action.")]
    Unauthorized,
    #[msg("Staking pool is currently paused.")]
    PoolPaused,
    #[msg("Insufficient staked balance.")]
    InsufficientStaked,
    #[msg("No rewards available to claim.")]
    NoRewards,
}
