# 🎓 Student Loan Tracker

A decentralized student loan tracking system built on the Stacks blockchain using Clarity smart contracts. Track repayment of crypto-backed student loans with full transparency and immutable records.

## 🌟 Features

- **🔐 Collateral-Based Loans**: Secure student loans backed by STX cryptocurrency
- **📊 Transparent Tracking**: All loan data stored on-chain with immutable payment history
- **💰 Interest Calculation**: Automated interest calculations based on time elapsed
- **⚡ Real-time Payments**: Make payments directly through the blockchain
- **🚨 Default Management**: Automated loan default handling for overdue payments
- **📈 Statistics Dashboard**: View comprehensive loan statistics and analytics

## 🚀 Getting Started

### Prerequisites

- [Clarinet CLI](https://github.com/hirosystems/clarinet) installed
- [Node.js](https://nodejs.org/) for testing
- Stacks wallet for interactions

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/Student-Loan-Tracker.git
cd Student-Loan-Tracker
```

2. Check contract compilation:
```bash
clarinet check
```

3. Run tests:
```bash
npm install
npm test
```

## 📝 Contract Functions

### 📋 Read-Only Functions

- `get-loan(loan-id)` - Get loan details by ID
- `get-borrower-loans(borrower)` - Get all loans for a borrower
- `get-collateral-balance(borrower)` - Get collateral balance for a borrower
- `get-outstanding-balance(loan-id)` - Calculate outstanding balance including interest
- `is-loan-overdue(loan-id)` - Check if loan is overdue
- `get-contract-stats()` - Get overall contract statistics
- `get-loan-payment-count(loan-id)` - Get number of payments made for a loan
- `get-payment-by-id(loan-id, payment-id)` - Get specific payment details

### 🔧 Public Functions

- `deposit-collateral(amount)` - Deposit STX as collateral
- `withdraw-collateral(amount)` - Withdraw available collateral
- `create-loan(amount, collateral-amount, interest-rate, duration-blocks)` - Create a new loan
- `make-payment(loan-id, payment-amount)` - Make a payment towards a loan
- `default-loan(loan-id)` - Mark loan as defaulted (owner only)

## 💡 Usage Examples

### Creating a Loan

```clarity
;; First deposit collateral
(contract-call? .student-loan-tracker deposit-collateral u1000000)

;; Create a loan with 10% interest rate for 50,000 blocks
(contract-call? .student-loan-tracker create-loan u500000 u1000000 u10 u50000)
```

### Making Payments

```clarity
;; Make a payment of 50,000 micro-STX towards loan ID 1
(contract-call? .student-loan-tracker make-payment u1 u50000)
```

### Checking Loan Status

```clarity
;; Get loan details
(contract-call? .student-loan-tracker get-loan u1)

;; Check outstanding balance
(contract-call? .student-loan-tracker get-outstanding-balance u1)

;; Check if loan is overdue
(contract-call? .student-loan-tracker is-loan-overdue u1)
```

## 🔒 Security Features

- **🛡️ Access Control**: Only borrowers can make payments on their loans
- **💎 Collateral Protection**: Collateral is locked until loan completion or default
- **⏰ Time-based Interest**: Interest calculated based on Stacks block height
- **🚫 Invalid Operation Prevention**: Comprehensive error handling and validation

## 📊 Error Codes

- `u1` - ERR_UNAUTHORIZED: Caller not authorized for operation
- `u2` - ERR_LOAN_NOT_FOUND: Loan ID does not exist
- `u3` - ERR_INVALID_AMOUNT: Invalid amount provided
- `u4` - ERR_LOAN_ALREADY_PAID: Loan already fully paid
- `u5` - ERR_INSUFFICIENT_COLLATERAL: Not enough collateral deposited
- `u6` - ERR_LOAN_NOT_ACTIVE: Loan is not active
- `u7` - ERR_INVALID_DURATION: Invalid loan duration
- `u8` - ERR_PAYMENT_OVERDUE: Payment is overdue
- `u9` - ERR_COLLATERAL_LOCKED: Collateral is locked in active loans
- `u10` - ERR_INVALID_INTEREST_RATE: Interest rate exceeds maximum (50%)

## 🏗️ Contract Architecture

The contract uses several key data structures:

- **Loans Map**: Stores loan details including amounts, interest rates, and status
- **Borrower Loans Map**: Tracks loans by borrower address
- **Collateral Deposits Map**: Manages collateral balances
- **Payment History Map**: Immutable record of all payments
- **Statistical Variables**: Track global loan metrics

