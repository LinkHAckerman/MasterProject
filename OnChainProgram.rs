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

#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
}

impl Vault {
    pub const LEN: usize = 32 + 1 + 8; // Pubkey + bump + u64
}

#[error_code]
pub enum ErrorCode {
    #[msg("Overflow occurred during arithmetic operation")]
    Overflow,
    #[msg("Underflow occurred during arithmetic operation")]
    Underflow,
    #[msg("Insufficient funds in vault")]
    InsufficientFunds,
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
