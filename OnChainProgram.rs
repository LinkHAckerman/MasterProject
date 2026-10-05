use solana_program::{ account_info::next_accounts, entrypoint, entrypoint::ProgramResult, pubkey::Pubkey, msg };

#[derive(BorshDeserialize, BorshSerialize)]
pub struct Escrow {
    pub sender: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EscrowError {
    NotEnoughFunds,
    InvalidAccount,
}

impl From<EscrowError> for ProgramError {
    fn from(e: EscrowError) -> ProgramError {
        ProgramError::Custom(e as u32)
    }
}

entrypoint!(process_instruction);

fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    let accounts_iter = &mut next_accounts(accounts);
    let instruction = instruction_data[0];
    match instruction {
        0 => {
            // Initialize escrow
            let sender = accounts_iter.next().unwrap();
            let recipient = accounts_iter.next().unwrap();
            let system_program = accounts_iter.next().unwrap();
            let amount = u64::from_le_bytes([instruction_data[1], instruction_data[2], instruction_data[3], instruction_data[4], instruction_data[5], instruction_data[6], instruction_data[7], instruction_data[8]]);
            if **sender.lamports.borrow() < amount {
                return Err(ProgramError::InsufficientFunds);
            }
            **sender.lamports.borrow_mut() -= amount;
            **recipient.lamports.borrow_mut() += amount;
            msg!("Escrow initialized: {} -> {} lamports", sender.key, amount);
        }
        1 => {
            msg!("Take funds instruction executed");
        }
        _ => {
            return Err(ProgramError::InvalidInstructionData);
        }
    }
    Ok(())
}
