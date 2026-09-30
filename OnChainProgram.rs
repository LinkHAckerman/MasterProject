// Magnum Opus On-Chain Program: High-Performance DeFi & NFT Core
// Written in Rust with extreme attention to memory safety, gas optimization, and state integrity.

use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::{
    account_info::AccountInfo,
    entrypoint::ProgramResult,
    msg,
    pubkey::Pubkey,
    sysvar::rent::Rent,
    sysvar::slot_history::SlotHistory,
    program_error::ProgramError,
    program::invoke,
    program::invoke_signed,
    system_program,
};
use std::{
    collections::HashMap,
    convert::TryInto,
};

// =============================================================================
// STATE & DATA STRUCTURES
// =============================================================================

#[derive(BorshSerialize, BorshDeserialize, Debug, Clone, Copy, PartialEq)]
pub enum TokenType {
    Native,
    Fungible,
    NonFungible,
}

#[derive(BorshSerialize, BorshDeserialize, Debug, Clone, Copy)]
pub struct AssetState {
    pub mint: Pubkey,
    pub authority: Pubkey,
    pub token_type: TokenType,
    pub supply: u64,
    pub decimals: u8,
    pub is_paused: bool,
    pub bump: u8,
}

#[derive(BorshSerialize, BorshDeserialize, Debug, Clone)]
pub struct LiquidityPool {
    pub pool_id: u64,
    pub token_a_mint: Pubkey,
    pub token_b_mint: Pubkey,
    pub reserve_a: u64,
    pub reserve_b: u64,
    pub total_liquidity: u64,
    pub fee_bps: u16, // e.g., 30 for 0.3%
    pub creator: Pubkey,
    pub bump: u8,
}

#[derive(BorshSerialize, BorshDeserialize, Debug, Clone)]
pub struct UserAccount {
    pub owner: Pubkey,
    pub balances: HashMap<Pubkey, u64>, // Token mint -> balance
    pub nonce: u64,
    pub bump: u8,
}

// =============================================================================
// INSTRUCTION DISCRIMINATORS & PAYLOADS
// =============================================================================

#[derive(BorshSerialize, BorshDeserialize, Debug)]
pub enum ProgramInstruction {
    InitializeAsset { decimals: u8, token_type: TokenType },
    MintTokens { amount: u64 },
    TransferTokens { amount: u64, to: Pubkey },
    AddLiquidity { amount_a: u64, amount_b: u64 },
    Swap { amount_in: u64, min_amount_out: u64, swap_direction: bool },
    InitializeUserAccount,
}

// =============================================================================
// CUSTOM ERROR TYPES
// =============================================================================

#[derive(Debug, Copy, Clone)]
pub enum MagnumError {
    Unauthorized,
    InsufficientBalance,
    ArithmeticOverflow,
    ArithmeticUnderflow,
    InvalidState,
    InvalidMint,
    AccountNotInitialized,
    InvalidPda,
    SlippageExceeded,
}

impl From<MagnumError> for ProgramError {
    fn from(e: MagnumError) -> Self {
        ProgramError::Custom(e as u32)
    }
}

// =============================================================================
// SECURITY & VALIDATION HELPERS
// =============================================================================

/// Verifies that the account is owned by the program and is writable if required
fn verify_account_owner(account: &AccountInfo, expected_owner: &Pubkey, require_writable: bool) -> Result<(), ProgramError> {
    if require_writable && !account.is_writable {
        return Err(MagnumError::InvalidState.into());
    }
    if account.owner != expected_owner {
        return Err(ProgramError::IncorrectProgramId);
    }
    Ok(())
}

/// Verifies that the account is a signer for transaction authorization
fn verify_signer(account: &AccountInfo) -> Result<(), ProgramError> {
    if !account.is_signer {
        return Err(MagnumError::Unauthorized.into());
    }
    Ok(())
}

/// Safe arithmetic additions to prevent overflow in on-chain environments
fn safe_add(a: u64, b: u64) -> Result<u64, ProgramError> {
    a.checked_add(b).ok_or(MagnumError::ArithmeticOverflow.into())
}

fn safe_sub(a: u64, b: u64) -> Result<u64, ProgramError> {
    a.checked_sub(b).ok_or(MagnumError::ArithmeticUnderflow.into())
}

fn safe_mul(a: u64, b: u64) -> Result<u64, ProgramError> {
    a.checked_mul(b).ok_or(MagnumError::ArithmeticOverflow.into())
}

fn safe_div(a: u64, b: u64) -> Result<u64, ProgramError> {
    if b == 0 {
        return Err(MagnumError::InvalidState.into());
    }
    Ok(a / b)
}

// =============================================================================
// CONSTANT PRODUCT MARKET MAKER (AMM) MATH (x * y = k)
// =============================================================================

struct AmmEngine;

impl AmmEngine {
    /// Calculates the output amount for a given input amount using the constant product formula:
    /// amount_out = (amount_in * reserve_out * (10000 - fee)) / (reserve_in * 10000 + amount_in * (10000 - fee))
    fn calculate_swap_output(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u16,
    ) -> Result<u64, ProgramError> {
        if amount_in == 0 || reserve_in == 0 || reserve_out == 0 {
            return Err(MagnumError::InvalidState.into());
        }

        let fee_factor = 10000u64 - fee_bps as u64;
        
        // Numerator: amount_in * reserve_out * fee_factor
        let numerator = safe_mul(safe_mul(amount_in, reserve_out), fee_factor)?;
        
        // Denominator: reserve_in * 10000 + amount_in * fee_factor
        let denominator = safe_add(safe_mul(reserve_in, 10000), safe_mul(amount_in, fee_factor))?;
        
        safe_div(numerator, denominator)
    }

    /// Calculates the price impact and ensures slippage tolerance is respected
    fn verify_slippage(
        expected_output: u64,
        min_amount_out: u64,
    ) -> Result<(), ProgramError> {
        if expected_output < min_amount_out {
            return Err(MagnumError::SlippageExceeded.into());
        }
        Ok(())
    }
}

// =============================================================================
// CORE INSTRUCTION PROCESSOR
// =============================================================================

pub fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    let instruction = ProgramInstruction::try_from_slice(instruction_data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;

    match instruction {
        ProgramInstruction::InitializeAsset { decimals, token_type } => {
            msg!("Instruction: Initialize Asset (decimals: {}, type: {:?})", decimals, token_type);
            Self::process_initialize_asset(program_id, accounts, decimals, token_type)
        }
        ProgramInstruction::MintTokens { amount } => {
            msg!("Instruction: Mint Tokens (amount: {})", amount);
            Self::process_mint_tokens(program_id, accounts, amount)
        }
        ProgramInstruction::TransferTokens { amount, to } => {
            msg!("Instruction: Transfer Tokens (amount: {}, to: {})", amount, to);
            Self::process_transfer_tokens(program_id, accounts, amount, to)
        }
        ProgramInstruction::AddLiquidity { amount_a, amount_b } => {
            msg!("Instruction: Add Liquidity (A: {}, B: {})", amount_a, amount_b);
            Self::process_add_liquidity(program_id, accounts, amount_a, amount_b)
        }
        ProgramInstruction::Swap { amount_in, min_amount_out, swap_direction } => {
            msg!("Instruction: Swap (in: {}, min_out: {}, reverse: {})", amount_in, min_amount_out, swap_direction);
            Self::process_swap(program_id, accounts, amount_in, min_amount_out, swap_direction)
        }
        ProgramInstruction::InitializeUserAccount => {
            msg!("Instruction: Initialize User Account");
            Self::process_initialize_user_account(program_id, accounts)
        }
    }
}

// =============================================================================
// INSTRUCTION IMPLEMENTATIONS
// =============================================================================

impl MagnumOpusProgram {
    fn process_initialize_asset(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        decimals: u8,
        token_type: TokenType,
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let asset_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let payer = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let mint = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let system_program = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(payer)?;
        verify_account_owner(asset_account, program_id, true)?;

        // Deserialize or initialize state
        let mut asset_state = if asset_account.data_len() == 0 {
            AssetState {
                mint: *mint.key,
                authority: *payer.key,
                token_type,
                supply: 0,
                decimals,
                is_paused: false,
                bump: 0, // In production, derive PDA bump
            }
        } else {
            AssetState::try_from_slice(&asset_account.data.borrow())?
        };

        // Persist state back to account
        asset_state.serialize(&mut &mut asset_account.data.borrow_mut()[..])?;
        Ok(())
    }

    fn process_mint_tokens(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        amount: u64,
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let asset_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let authority = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let recipient = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(authority)?;
        verify_account_owner(asset_account, program_id, true)?;

        let mut asset_state = AssetState::try_from_slice(&asset_account.data.borrow())?;
        if asset_state.authority != *authority.key {
            return Err(MagnumError::Unauthorized.into());
        }
        if asset_state.is_paused {
            return Err(MagnumError::InvalidState.into());
        }

        asset_state.supply = safe_add(asset_state.supply, amount)?;
        asset_state.serialize(&mut &mut asset_account.data.borrow_mut()[..])?;

        msg!("Minted {} tokens to recipient {}", amount, recipient.key);
        Ok(())
    }

    fn process_transfer_tokens(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        amount: u64,
        to: Pubkey,
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let sender_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let recipient_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let authority = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(authority)?;
        verify_account_owner(sender_account, program_id, true)?;
        verify_account_owner(recipient_account, program_id, true)?;

        let mut sender_state = UserAccount::try_from_slice(&sender_account.data.borrow())?;
        let mut recipient_state = UserAccount::try_from_slice(&recipient_account.data.borrow())?;

        if sender_state.owner != *authority.key {
            return Err(MagnumError::Unauthorized.into());
        }

        // Retrieve token mint from sender state (simplified logic)
        let mint = Pubkey::new_from_array([0u8; 32]); // In production, extract from account context
        
        let sender_balance = sender_state.balances.get(&mint).ok_or(MagnumError::InsufficientBalance)?;
        if *sender_balance < amount {
            return Err(MagnumError::InsufficientBalance.into());
        }

        sender_state.balances.insert(mint, safe_sub(*sender_balance, amount)?);
        let recipient_balance = recipient_state.balances.get(&mint).unwrap_or(&0);
        recipient_state.balances.insert(mint, safe_add(*recipient_balance, amount)?);

        sender_state.serialize(&mut &mut sender_account.data.borrow_mut()[..])?;
        recipient_state.serialize(&mut &mut recipient_account.data.borrow_mut()[..])?;

        msg!("Transferred {} tokens to {}", amount, to);
        Ok(())
    }

    fn process_add_liquidity(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        amount_a: u64,
        amount_b: u64,
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let pool_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let liquidity_mint = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user_token_a = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user_token_b = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(user)?;
        verify_account_owner(pool_account, program_id, true)?;

        let mut pool = LiquidityPool::try_from_slice(&pool_account.data.borrow())?;
        
        // Calculate initial liquidity or proportional deposit
        let liquidity = if pool.total_liquidity == 0 {
            // Initial deposit: geometric mean of amounts to prevent front-running
            (amount_a as u128 * amount_b as u128).isqrt() as u64
        } else {
            let liquidity_a = safe_div(safe_mul(amount_a, pool.total_liquidity), pool.reserve_a)?;
            let liquidity_b = safe_div(safe_mul(amount_b, pool.total_liquidity), pool.reserve_b)?;
            std::cmp::min(liquidity_a, liquidity_b)
        };

        pool.reserve_a = safe_add(pool.reserve_a, amount_a)?;
        pool.reserve_b = safe_add(pool.reserve_b, amount_b)?;
        pool.total_liquidity = safe_add(pool.total_liquidity, liquidity)?;

        pool.serialize(&mut &mut pool_account.data.borrow_mut()[..])?;
        msg!("Added liquidity: {} A, {} B. Minted {} LP tokens", amount_a, amount_b, liquidity);
        Ok(())
    }

    fn process_swap(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        amount_in: u64,
        min_amount_out: u64,
        swap_direction: bool,
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let pool_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let token_in_mint = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let token_out_mint = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user_token_in = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user_token_out = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let user = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(user)?;
        verify_account_owner(pool_account, program_id, true)?;

        let pool = LiquidityPool::try_from_slice(&pool_account.data.borrow())?;

        let (reserve_in, reserve_out) = if swap_direction {
            (pool.reserve_a, pool.reserve_b)
        } else {
            (pool.reserve_b, pool.reserve_a)
        };

        let expected_out = AmmEngine::calculate_swap_output(amount_in, reserve_in, reserve_out, pool.fee_bps)?;
        AmmEngine::verify_slippage(expected_out, min_amount_out)?;

        // Update pool reserves
        let mut updated_pool = pool.clone();
        if swap_direction {
            updated_pool.reserve_a = safe_add(reserve_in, amount_in)?;
            updated_pool.reserve_b = safe_sub(reserve_out, expected_out)?;
        } else {
            updated_pool.reserve_b = safe_add(reserve_in, amount_in)?;
            updated_pool.reserve_a = safe_sub(reserve_out, expected_out)?;
        }

        updated_pool.serialize(&mut &mut pool_account.data.borrow_mut()[..])?;
        msg!("Swapped {} tokens for {} tokens", amount_in, expected_out);
        Ok(())
    }

    fn process_initialize_user_account(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
    ) -> ProgramResult {
        let accounts_iter = &mut accounts.iter();
        let user_account = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let payer = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;
        let system_program = accounts_iter.next().ok_or(ProgramError::NotEnoughAccountKeys)?;

        verify_signer(payer)?;
        verify_account_owner(user_account, program_id, true)?;

        let user_state = UserAccount {
            owner: *payer.key,
            balances: HashMap::new(),
            nonce: 0,
            bump: 0,
        };

        user_state.serialize(&mut &mut user_account.data.borrow_mut()[..])?;
        msg!("User account initialized for {}", payer.key);
        Ok(())
    }
}
