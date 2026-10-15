use anchor_lang::prelude::*;

declare_id!("MagnumOpus1111111111111111111111111111111111");

#[program]
pub mod on_chain_program {
    use super::*;

    /// Initialize a new vault for the given authority.
    /// The vault is a PDA seeded with "vault" and the bump.
    pub fn initialize(ctx: Context<Initialize>, bump: u8) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = *ctx.accounts.authority.key;
        vault.bump = bump;
        vault.balance = 0;
        vault.staked_balance = 0;
        vault.reward_debt = 0;
        vault.created_at = Clock::get()?.unix_timestamp;
        emit!(VaultInitialized { authority: vault.authority, bump });
        Ok(())
    }

    /// Deposit lamports into the vault.
    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.balance = vault
            .balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
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
        // Transfer lamports back to the authority.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(WithdrawEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Change the authority of the vault. Only the current authority can call.
    pub fn set_authority(ctx: Context<SetAuthority>, new_authority: Pubkey) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = new_authority;
        emit!(AuthorityChanged { old_authority: *ctx.accounts.current_authority.key, new_authority });
        Ok(())
    }

    /// Stake tokens from the vault into the DeFi staking pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        require!(amount > 0, ErrorCode::InvalidAmount);

        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;

        // Update reward debt based on current reward per stake
        let clock = Clock::get()?;
        let staking_pool = &ctx.accounts.staking_pool;
        let reward_per_token = staking_pool.reward_per_token;
        let user_reward_per_token_paid = vault.reward_per_token_paid;

        // Calculate pending rewards
        let staked = vault.staked_balance;
        let pending_rewards = (staked as u128)
            .checked_mul((reward_per_token - user_reward_per_token_paid) as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(1_000_000_000)? as u64;

        vault.pending_rewards = vault.pending_rewards.checked_add(pending_rewards).ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        emit!(StakeEvent {
            authority: vault.authority,
            amount,
            total_staked: vault.staked_balance,
            pending_rewards: vault.pending_rewards,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Unstake tokens from the staking pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientFunds);
        require!(amount > 0, ErrorCode::InvalidAmount);

        // Update rewards before unstaking
        let staking_pool = &ctx.accounts.staking_pool;
        let reward_per_token = staking_pool.reward_per_token;
        let pending_rewards = (vault.staked_balance as u128)
            .checked_mul((reward_per_token - vault.reward_per_token_paid) as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(1_000_000_000)? as u64;

        vault.pending_rewards = vault.pending_rewards.checked_add(pending_rewards).ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.balance = vault.balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;

        emit!(UnstakeEvent {
            authority: vault.authority,
            amount,
            total_staked: vault.staked_balance,
            pending_rewards: vault.pending_rewards,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Claim pending staking rewards.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &ctx.accounts.staking_pool;

        // Update reward debt
        let reward_per_token = staking_pool.reward_per_token;
        let pending_rewards = (vault.staked_balance as u128)
            .checked_mul((reward_per_token - vault.reward_per_token_paid) as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(1_000_000_000)? as u64;

        vault.pending_rewards = vault.pending_rewards.checked_add(pending_rewards).ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        let rewards = vault.pending_rewards;
        require!(rewards > 0, ErrorCode::InvalidAmount);

        vault.pending_rewards = 0;

        // Transfer rewards from staking pool to vault
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= rewards;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += rewards;

        emit!(RewardsClaimedEvent {
            authority: vault.authority,
            amount: rewards,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Mint a new NFT to the vault's collection.
    pub fn mint_nft(ctx: Context<MintNFT>, name: String, symbol: String, uri: String) -> Result<()> {
        let vault = &ctx.accounts.vault;
        let nft_mint = &ctx.accounts.nft_mint;
        let nft_token_account = &ctx.accounts.nft_token_account;

        require!(name.len() <= 32, ErrorCode::NameTooLong);
        require!(symbol.len() <= 10, ErrorCode::NameTooLong);
        require!(uri.len() <= 200, ErrorCode::UriTooLong);

        // Mint NFT to the vault's token account
        anchor_spl::token::mint(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                anchor_spl::token::Mint {
                    mint: nft_mint.to_account_info(),
                    authority: vault.to_account_info(),
                },
            ),
            1,
        )?;

        // Create token account for the NFT
        anchor_spl::token::initialize(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                anchor_spl::token::Initialize {
                    account: nft_token_account.to_account_info(),
                    mint: nft_mint.to_account_info(),
                    authority: vault.to_account_info(),
                    token_program_id: ctx.accounts.token_program.to_account_info(),
                },
            ),
        )?;

        emit!(NFTMintedEvent {
            vault: *vault.key,
            mint: *nft_mint.key,
            name,
            symbol,
            uri,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Update the staking reward rate. Only the staking pool authority can call.
    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_reward_rate: u64) -> Result<()> {
        let staking_pool = &mut ctx.accounts.staking_pool;
        let clock = Clock::get()?;

        // Accrue pending rewards
        let elapsed = clock.unix_timestamp - staking_pool.last_update_time;
        if elapsed > 0 && staking_pool.total_staked > 0 {
            let new_rewards = (elapsed as u128)
                .checked_mul(new_reward_rate as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(1_000_000_000)? as u64;

            staking_pool.reward_per_token = staking_pool.reward_per_token
                .checked_add(
                    (new_rewards as u128)
                        .checked_mul(1_000_000_000)
                        .ok_or(ErrorCode::Overflow)?
                        .checked_div(staking_pool.total_staked as u128)
                        .ok_or(ErrorCode::Overflow)? as u64,
                )
                .ok_or(ErrorCode::Overflow)?;

            staking_pool.last_update_time = clock.unix_timestamp;
        }

        staking_pool.reward_rate = new_reward_rate;

        emit!(RewardRateUpdatedEvent {
            old_rate: staking_pool.reward_rate,
            new_rate: new_reward_rate,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }
}

/// Context for initializing a vault.
#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct Initialize<'info> {
    #[account(init, seeds = [b"vault".as_ref()], bump = bump, payer = authority, space = 8 + Vault::LEN)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

/// Context for depositing lamports.
#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

/// Context for withdrawing lamports.
#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

/// Context for changing authority.
#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump, has_one = current_authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub current_authority: Signer<'info>,
}

/// Context for staking.
#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [b"staking_pool".as_ref()], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    pub system_program: Program<'info, System>,
}

/// Context for unstaking.
#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [b"staking_pool".as_ref()], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    pub system_program: Program<'info, System>,
}

/// Context for claiming rewards.
#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [b"staking_pool".as_ref()], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    pub system_program: Program<'info, System>,
}

/// Context for minting NFTs.
#[derive(Accounts)]
pub struct MintNFT<'info> {
    #[account(mut, seeds = [b"vault".as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub nft_mint: Signer<'info>,
    /// CHECK: Token account is initialized by the program
    #[account(mut)]
    pub nft_token_account: AccountInfo<'info>,
    pub token_program: Program<'info, anchor_spl::token::Token>,
    pub system_program: Program<'info, System>,
}

/// Context for updating reward rate.
#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(mut, seeds = [b"staking_pool".as_ref()], bump = staking_pool.bump, has_one = authority)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, signer)]
    pub authority: Signer<'info>,
}

#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub pending_rewards: u64,
    pub reward_per_token_paid: u64,
    pub created_at: i64,
}

impl Vault {
    pub const LEN: usize = 32 + 1 + 8 + 8 + 8 + 8 + 8; // Pubkey + bump + u64 fields + i64
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub reward_rate: u64,
    pub reward_per_token: u64,
    pub total_staked: u64,
    pub last_update_time: i64,
    pub created_at: i64,
}

impl StakingPool {
    pub const LEN: usize = 32 + 1 + 8 + 8 + 8 + 8 + 8; // Pubkey + bump + u64 fields + i64
}

#[error_code]
pub enum ErrorCode {
    #[msg("Overflow occurred during arithmetic operation")]
    Overflow,
    #[msg("Underflow occurred during arithmetic operation")]
    Underflow,
    #[msg("Insufficient funds in vault")]
    InsufficientFunds,
    #[msg("Invalid amount provided")]
    InvalidAmount,
    #[msg("Name exceeds maximum length")]
    NameTooLong,
    #[msg("URI exceeds maximum length")]
    UriTooLong,
}

/// Event emitted when a vault is initialized.
#[event]
pub struct VaultInitialized {
    pub authority: Pubkey,
    pub bump: u8,
}

/// Event emitted on deposit.
#[event]
pub struct DepositEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

/// Event emitted on withdrawal.
#[event]
pub struct WithdrawEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

/// Event emitted when authority changes.
#[event]
pub struct AuthorityChanged {
    pub old_authority: Pubkey,
    pub new_authority: Pubkey,
}

/// Event emitted on stake.
#[event]
pub struct StakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
    pub pending_rewards: u64,
    pub timestamp: i64,
}

/// Event emitted on unstake.
#[event]
pub struct UnstakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
    pub pending_rewards: u64,
    pub timestamp: i64,
}

/// Event emitted when rewards are claimed.
#[event]
pub struct RewardsClaimedEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

/// Event emitted when an NFT is minted.
#[event]
pub struct NFTMintedEvent {
    pub vault: Pubkey,
    pub mint: Pubkey,
    pub name: String,
    pub symbol: String,
    pub uri: String,
    pub timestamp: i64,
}

/// Event emitted when reward rate is updated.
#[event]
pub struct RewardRateUpdatedEvent {
    pub old_rate: u64,
    pub new_rate: u64,
    pub timestamp: i64,
}