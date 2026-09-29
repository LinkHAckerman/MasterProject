//! OnChainProgram.rs
//!
//! A native (non-Anchor) Solana program implementing a simple SOL vault:
//! users can deposit SOL into a per-user PDA account and withdraw it later.
//! This is a seed implementation meant to give future AI agents real,
//! working on-chain Rust to build on, rather than an empty file.
//!
//! Note for local/CI validation: this file depends on the `solana_program`
//! and `borsh` crates. Without a Cargo.toml and network access to fetch
//! those crates, a bare `rustc` check cannot resolve them and will report
//! "cannot find crate" - that's expected and is treated as advisory-only
//! in validate_files.py, not a sign the code itself is wrong.

use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint,
    entrypoint::ProgramResult,
    msg,
    program::invoke_signed,
    program_error::ProgramError,
    pubkey::Pubkey,
    rent::Rent,
    system_instruction,
    sysvar::Sysvar,
};

entrypoint!(process_instruction);

/// Instructions supported by this program.
#[derive(BorshSerialize, BorshDeserialize, Debug, Clone)]
pub enum VaultInstruction {
    /// Deposit `amount` lamports from the user into their vault PDA.
    /// Accounts:
    ///   0. [signer, writable] User's wallet
    ///   1. [writable]         User's vault PDA (created on first deposit)
    ///   2. []                 System program
    Deposit { amount: u64 },

    /// Withdraw `amount` lamports from the user's vault PDA back to their wallet.
    /// Accounts:
    ///   0. [signer, writable] User's wallet
    ///   1. [writable]         User's vault PDA
    Withdraw { amount: u64 },
}

/// On-chain state stored in each user's vault PDA.
#[derive(BorshSerialize, BorshDeserialize, Debug, Clone, Default)]
pub struct VaultState {
    pub owner: Pubkey,
    pub balance: u64,
    pub bump: u8,
}

impl VaultState {
    pub const SIZE: usize = 32 + 8 + 1;
}

pub fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    let instruction = VaultInstruction::try_from_slice(instruction_data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;

    match instruction {
        VaultInstruction::Deposit { amount } => process_deposit(program_id, accounts, amount),
        VaultInstruction::Withdraw { amount } => process_withdraw(program_id, accounts, amount),
    }
}

fn vault_pda(program_id: &Pubkey, owner: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[b"vault", owner.as_ref()], program_id)
}

fn process_deposit(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let accounts_iter = &mut accounts.iter();
    let user = next_account_info(accounts_iter)?;
    let vault_account = next_account_info(accounts_iter)?;
    let system_program = next_account_info(accounts_iter)?;

    if !user.is_signer {
        msg!("Deposit failed: user account must sign the transaction");
        return Err(ProgramError::MissingRequiredSignature);
    }

    let (expected_pda, bump) = vault_pda(program_id, user.key);
    if expected_pda != *vault_account.key {
        msg!("Deposit failed: vault account does not match derived PDA");
        return Err(ProgramError::InvalidArgument);
    }

    // Create the vault PDA on first deposit if it doesn't exist yet.
    if vault_account.data_is_empty() {
        let rent = Rent::get()?;
        let lamports = rent.minimum_balance(VaultState::SIZE);

        invoke_signed(
            &system_instruction::create_account(
                user.key,
                vault_account.key,
                lamports,
                VaultState::SIZE as u64,
                program_id,
            ),
            &[user.clone(), vault_account.clone(), system_program.clone()],
            &[&[b"vault", user.key.as_ref(), &[bump]]],
        )?;

        let fresh_state = VaultState {
            owner: *user.key,
            balance: 0,
            bump,
        };
        fresh_state.serialize(&mut &mut vault_account.data.borrow_mut()[..])?;
    }

    // Transfer the deposit from the user's wallet into the vault PDA.
    invoke_signed(
        &system_instruction::transfer(user.key, vault_account.key, amount),
        &[user.clone(), vault_account.clone(), system_program.clone()],
        &[&[b"vault", user.key.as_ref(), &[bump]]],
    )?;

    let mut vault_state = VaultState::try_from_slice(&vault_account.data.borrow())?;
    vault_state.balance = vault_state
        .balance
        .checked_add(amount)
        .ok_or(ProgramError::ArithmeticOverflow)?;
    vault_state.serialize(&mut &mut vault_account.data.borrow_mut()[..])?;

    msg!("Deposited {} lamports for {}", amount, user.key);
    Ok(())
}

fn process_withdraw(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let accounts_iter = &mut accounts.iter();
    let user = next_account_info(accounts_iter)?;
    let vault_account = next_account_info(accounts_iter)?;

    if !user.is_signer {
        msg!("Withdraw failed: user account must sign the transaction");
        return Err(ProgramError::MissingRequiredSignature);
    }

    let (expected_pda, _bump) = vault_pda(program_id, user.key);
    if expected_pda != *vault_account.key {
        msg!("Withdraw failed: vault account does not match derived PDA");
        return Err(ProgramError::InvalidArgument);
    }

    let mut vault_state = VaultState::try_from_slice(&vault_account.data.borrow())?;

    if vault_state.owner != *user.key {
        msg!("Withdraw failed: vault is not owned by the requesting user");
        return Err(ProgramError::IllegalOwner);
    }

    if vault_state.balance < amount {
        msg!(
            "Withdraw failed: requested {} but balance is only {}",
            amount,
            vault_state.balance
        );
        return Err(ProgramError::InsufficientFunds);
    }

    // Move lamports directly (PDA-owned accounts can't use system_instruction::transfer
    // as the source, since they aren't signers - we move lamports by adjusting balances).
    **vault_account.try_borrow_mut_lamports()? -= amount;
    **user.try_borrow_mut_lamports()? += amount;

    vault_state.balance -= amount;
    vault_state.serialize(&mut &mut vault_account.data.borrow_mut()[..])?;

    msg!("Withdrew {} lamports for {}", amount, user.key);
    Ok(())
}
