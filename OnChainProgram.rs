use anchor_lang::prelude::*;
use anchor_lang::solana_program::program::invoke;
use anchor_lang::solana_program::system_instruction;

declare_id!("MagnumOpus1111111111111111111111111111111111");

pub const REWARD_PRECISION: u128 = 1_000_000_000;
pub const FEE_DENOMINATOR: u64 = 10_000;
pub const MAX_NAME_LEN: usize = 32;
pub const MAX_DESC_LEN: usize = 64;

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

    /// Initialize user staking account PDA.
    pub fn initialize_user_staking(ctx: Context<InitializeUserStaking>, bump: u8) -> Result<()> {
        let user_acc = &mut ctx.accounts.user_staking;
        user_acc.user = ctx.accounts.user.key();
        user_acc.pool = ctx.accounts.staking_pool.key();
        user_acc.bump = bump;
        user_acc.staked_amount = 0;
        user_acc.reward_per_token_paid = ctx.accounts.staking_pool.reward_per_token;
        user_acc.pending_rewards = 0;
        user_acc.last_staked_at = Clock::get()?.unix_timestamp;
        emit!(UserStakingInitialized {
            user: user_acc.user,
            pool: user_acc.pool,
        });
        Ok(())
    }

    /// Stake tokens into the pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        require!(!pool.paused, ErrorCode::PoolIsPaused);

        let user_acc = &mut ctx.accounts.user_staking;
        update_pool_rewards(pool, Some(user_acc))?;

        user_acc.staked_amount = user_acc
            .staked_amount
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        user_acc.last_staked_at = Clock::get()?.unix_timestamp;

        pool.total_staked = pool
            .total_staked
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;

        // Transfer native SOL to pool PDA vault
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(StakedEvent {
            user: user_acc.user,
            amount,
            total_staked: user_acc.staked_amount,
        });
        Ok(())
    }

    /// Unstake tokens from the pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let user_acc = &mut ctx.accounts.user_staking;
        require!(user_acc.staked_amount >= amount, ErrorCode::InsufficientFunds);

        update_pool_rewards(pool, Some(user_acc))?;

        user_acc.staked_amount = user_acc
            .staked_amount
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        pool.total_staked = pool
            .total_staked
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;

        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(UnstakedEvent {
            user: user_acc.user,
            amount,
            remaining_staked: user_acc.staked_amount,
        });
        Ok(())
    }

    /// Claim accumulated yield rewards.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        let user_acc = &mut ctx.accounts.user_staking;
        update_pool_rewards(pool, Some(user_acc))?;

        let reward_amount = user_acc.pending_rewards;
        require!(reward_amount > 0, ErrorCode::InvalidAmount);

        user_acc.pending_rewards = 0;
        pool.total_rewards_distributed = pool
            .total_rewards_distributed
            .checked_add(reward_amount)
            .ok_or(ErrorCode::Overflow)?;

        emit!(RewardClaimed {
            user: user_acc.user,
            amount: reward_amount,
        });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Decentralized NFT Marketplace Module
    // ---------------------------------------------------------------------
    /// List an NFT for sale at a fixed price in lamports.
    pub fn initialize_nft_listing(
        ctx: Context<InitializeNftListing>,
        price: u64,
        bump: u8,
    ) -> Result<()> {
        require!(price > 0, ErrorCode::InvalidAmount);
        let listing = &mut ctx.accounts.nft_listing;
        listing.seller = ctx.accounts.seller.key();
        listing.nft_mint = ctx.accounts.nft_mint.key();
        listing.price = price;
        listing.is_active = true;
        listing.bump = bump;
        listing.created_at = Clock::get()?.unix_timestamp;

        emit!(NftListed {
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            price,
        });
        Ok(())
    }

    /// Buy a listed NFT.
    pub fn buy_nft(ctx: Context<BuyNft>) -> Result<()> {
        let listing = &mut ctx.accounts.nft_listing;
        require!(listing.is_active, ErrorCode::ListingInactive);

        let price = listing.price;
        let seller_info = ctx.accounts.seller.to_account_info();
        let buyer_info = ctx.accounts.buyer.to_account_info();

        // Transfer lamports from buyer to seller
        **buyer_info.try_borrow_mut_lamports()? -= price;
        **seller_info.try_borrow_mut_lamports()? += price;

        listing.is_active = false;

        emit!(NftSold {
            buyer: buyer_info.key(),
            seller: seller_info.key(),
            nft_mint: listing.nft_mint,
            price,
        });
        Ok(())
    }

    /// Cancel an active NFT listing.
    pub fn cancel_nft_listing(ctx: Context<CancelNftListing>) -> Result<()> {
        let listing = &mut ctx.accounts.nft_listing;
        require!(listing.seller == ctx.accounts.seller.key(), ErrorCode::Unauthorized);
        require!(listing.is_active, ErrorCode::ListingInactive);

        listing.is_active = false;

        emit!(NftListingCancelled {
            seller: listing.seller,
            nft_mint: listing.nft_mint,
        });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Governance & On-Chain Voting Module
    // ---------------------------------------------------------------------
    /// Create a governance proposal.
    pub fn create_proposal(
        ctx: Context<CreateProposal>,
        title: String,
        description: String,
        duration_seconds: i64,
        bump: u8,
    ) -> Result<()> {
        require!(duration_seconds > 0, ErrorCode::InvalidAmount);
        let proposal = &mut ctx.accounts.proposal;
        proposal.creator = ctx.accounts.creator.key();
        
        let mut title_bytes = [0u8; MAX_NAME_LEN];
        let t_bytes = title.as_bytes();
        let len = t_bytes.len().min(MAX_NAME_LEN);
        title_bytes[..len].copy_from_slice(&t_bytes[..len]);
        proposal.title = title_bytes;

        let mut desc_bytes = [0u8; MAX_DESC_LEN];
        let d_bytes = description.as_bytes();
        let d_len = d_bytes.len().min(MAX_DESC_LEN);
        desc_bytes[..d_len].copy_from_slice(&d_bytes[..d_len]);
        proposal.description = desc_bytes;

        let current_time = Clock::get()?.unix_timestamp;
        proposal.start_time = current_time;
        proposal.end_time = current_time.checked_add(duration_seconds).ok_or(ErrorCode::Overflow)?;
        proposal.yes_votes = 0;
        proposal.no_votes = 0;
        proposal.executed = false;
        proposal.bump = bump;

        emit!(ProposalCreated {
            creator: proposal.creator,
            start_time: proposal.start_time,
            end_time: proposal.end_time,
        });
        Ok(())
    }

    /// Cast a vote on an active proposal.
    pub fn vote_proposal(ctx: Context<VoteProposal>, approve: bool) -> Result<()> {
        let proposal = &mut ctx.accounts.proposal;
        let current_time = Clock::get()?.unix_timestamp;

        require!(current_time >= proposal.start_time && current_time <= proposal.end_time, ErrorCode::ProposalExpired);
        require!(!proposal.executed, ErrorCode::ProposalAlreadyExecuted);

        if approve {
            proposal.yes_votes = proposal.yes_votes.checked_add(1).ok_or(ErrorCode::Overflow)?;
        } else {
            proposal.no_votes = proposal.no_votes.checked_add(1).ok_or(ErrorCode::Overflow)?;
        }

        emit!(VotedEvent {
            voter: ctx.accounts.voter.key(),
            approve,
            yes_votes: proposal.yes_votes,
            no_votes: proposal.no_votes,
        });
        Ok(())
    }

    /// Execute a successful proposal after voting period closes.
    pub fn execute_proposal(ctx: Context<ExecuteProposal>) -> Result<()> {
        let proposal = &mut ctx.accounts.proposal;
        let current_time = Clock::get()?.unix_timestamp;

        require!(current_time > proposal.end_time, ErrorCode::ProposalActive);
        require!(!proposal.executed, ErrorCode::ProposalAlreadyExecuted);
        require!(proposal.yes_votes > proposal.no_votes, ErrorCode::Unauthorized);

        proposal.executed = true;

        emit!(ProposalExecuted {
            executor: ctx.accounts.executor.key(),
            yes_votes: proposal.yes_votes,
            no_votes: proposal.no_votes,
        });
        Ok(())
    }
}

// ---------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------
fn update_pool_rewards(
    pool: &mut StakingPool,
    user: Option<&mut UserStakingAccount>,
) -> Result<()> {
    let current_time = Clock::get()?.unix_timestamp;
    if current_time > pool.last_update_time {
        if pool.total_staked > 0 {
            let time_diff = (current_time - pool.last_update_time) as u128;
            let reward_delta = time_diff
                .checked_mul(pool.reward_rate_per_second as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_mul(REWARD_PRECISION)
                .ok_or(ErrorCode::Overflow)?;
            let added_reward = reward_delta
                .checked_div(pool.total_staked as u128)
                .ok_or(ErrorCode::Overflow)?;
            pool.reward_per_token = pool
                .reward_per_token
                .checked_add(added_reward)
                .ok_or(ErrorCode::Overflow)?;
        }
        pool.last_update_time = current_time;
    }

    if let Some(user_acc) = user {
        let pending = (user_acc.staked_amount as u128)
            .checked_mul(pool.reward_per_token.saturating_sub(user_acc.reward_per_token_paid))
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::Overflow)? as u64;

        user_acc.pending_rewards = user_acc
            .pending_rewards
            .checked_add(pending)
            .ok_or(ErrorCode::Overflow)?;
        user_acc.reward_per_token_paid = pool.reward_per_token;
    }
    Ok(())
}

// ---------------------------------------------------------------------
// Account Contexts
// ---------------------------------------------------------------------
#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 1 + 8 + 8 + 16 + 8 + 16 + 8 + 8,
        seeds = [b"vault", authority.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(
        mut,
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(
        mut,
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(
        mut,
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(reward_rate_per_second: u64, bump: u8)]
pub struct InitializeStakingPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 1 + 8 + 16 + 8 + 8 + 8 + 1,
        seeds = [b"staking_pool", authority.key().as_ref()],
        bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct InitializeUserStaking<'info> {
    #[account(
        init,
        payer = user,
        space = 8 + 32 + 32 + 1 + 8 + 16 + 8 + 8,
        seeds = [b"user_staking", staking_pool.key().as_ref(), user.key().as_ref()],
        bump
    )]
    pub user_staking: Account<'info, UserStakingAccount>,
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(
        mut,
        seeds = [b"user_staking", staking_pool.key().as_ref(), user.key().as_ref()],
        bump = user_staking.bump
    )]
    pub user_staking: Account<'info, UserStakingAccount>,
    #[account(mut)]
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(
        mut,
        seeds = [b"user_staking", staking_pool.key().as_ref(), user.key().as_ref()],
        bump = user_staking.bump
    )]
    pub user_staking: Account<'info, UserStakingAccount>,
    #[account(mut)]
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(
        mut,
        seeds = [b"user_staking", staking_pool.key().as_ref(), user.key().as_ref()],
        bump = user_staking.bump
    )]
    pub user_staking: Account<'info, UserStakingAccount>,
    pub user: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(price: u64, bump: u8)]
pub struct InitializeNftListing<'info> {
    #[account(
        init,
        payer = seller,
        space = 8 + 32 + 32 + 8 + 1 + 1 + 8,
        seeds = [b"nft_listing", seller.key().as_ref(), nft_mint.key().as_ref()],
        bump
    )]
    pub nft_listing: Account<'info, NftListing>,
    /// CHECK: Validated as NFT mint public key
    pub nft_mint: AccountInfo<'info>,
    #[account(mut)]
    pub seller: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct BuyNft<'info> {
    #[account(mut)]
    pub nft_listing: Account<'info, NftListing>,
    #[account(mut)]
    pub buyer: Signer<'info>,
    /// CHECK: Seller account receiving funds
    #[account(mut, address = nft_listing.seller)]
    pub seller: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct CancelNftListing<'info> {
    #[account(mut)]
    pub nft_listing: Account<'info, NftListing>,
    pub seller: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(title: String, description: String, duration_seconds: i64, bump: u8)]
pub struct CreateProposal<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + 32 + MAX_NAME_LEN + MAX_DESC_LEN + 8 + 8 + 8 + 8 + 1 + 1,
        seeds = [b"proposal", creator.key().as_ref(), title.as_bytes()],
        bump
    )]
    pub proposal: Account<'info, Proposal>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct VoteProposal<'info> {
    #[account(mut)]
    pub proposal: Account<'info, Proposal>,
    pub voter: Signer<'info>,
}

#[derive(Accounts)]
pub struct ExecuteProposal<'info> {
    #[account(mut)]
    pub proposal: Account<'info, Proposal>,
    pub executor: Signer<'info>,
}

// ---------------------------------------------------------------------
// Data Structures
// ---------------------------------------------------------------------
#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub reward_debt: u128,
    pub pending_rewards: u64,
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
pub struct UserStakingAccount {
    pub user: Pubkey,
    pub pool: Pubkey,
    pub bump: u8,
    pub staked_amount: u64,
    pub reward_per_token_paid: u128,
    pub pending_rewards: u64,
    pub last_staked_at: i64,
}

#[account]
pub struct NftListing {
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
    pub is_active: bool,
    pub bump: u8,
    pub created_at: i64,
}

#[account]
pub struct Proposal {
    pub creator: Pubkey,
    pub title: [u8; MAX_NAME_LEN],
    pub description: [u8; MAX_DESC_LEN],
    pub yes_votes: u64,
    pub no_votes: u64,
    pub start_time: i64,
    pub end_time: i64,
    pub executed: bool,
    pub bump: u8,
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
pub struct UserStakingInitialized {
    pub user: Pubkey,
    pub pool: Pubkey,
}

#[event]
pub struct StakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
}

#[event]
pub struct UnstakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub remaining_staked: u64,
}

#[event]
pub struct RewardClaimed {
    pub user: Pubkey,
    pub amount: u64,
}

#[event]
pub struct NftListed {
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
}

#[event]
pub struct NftSold {
    pub buyer: Pubkey,
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
}

#[event]
pub struct NftListingCancelled {
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
}

#[event]
pub struct ProposalCreated {
    pub creator: Pubkey,
    pub start_time: i64,
    pub end_time: i64,
}

#[event]
pub struct VotedEvent {
    pub voter: Pubkey,
    pub approve: bool,
    pub yes_votes: u64,
    pub no_votes: u64,
}

#[event]
pub struct ProposalExecuted {
    pub executor: Pubkey,
    pub yes_votes: u64,
    pub no_votes: u64,
}

// ---------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount provided.")]
    InvalidAmount,
    #[msg("Insufficient funds for this transaction.")]
    InsufficientFunds,
    #[msg("Unauthorized operation.")]
    Unauthorized,
    #[msg("Numerical overflow detected.")]
    Overflow,
    #[msg("Numerical underflow detected.")]
    Underflow,
    #[msg("Staking pool is currently paused.")]
    PoolIsPaused,
    #[msg("Staking pool is not paused.")]
    PoolNotPaused,
    #[msg("NFT listing is inactive or already purchased.")]
    ListingInactive,
    #[msg("Proposal voting period has expired.")]
    ProposalExpired,
    #[msg("Proposal voting period is still active.")]
    ProposalActive,
    #[msg("Proposal has already been executed.")]
    ProposalAlreadyExecuted,
}
