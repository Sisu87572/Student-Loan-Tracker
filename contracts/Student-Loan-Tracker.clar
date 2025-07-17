(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_LOAN_NOT_FOUND (err u2))
(define-constant ERR_INVALID_AMOUNT (err u3))
(define-constant ERR_LOAN_ALREADY_PAID (err u4))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u5))
(define-constant ERR_LOAN_NOT_ACTIVE (err u6))
(define-constant ERR_INVALID_DURATION (err u7))
(define-constant ERR_PAYMENT_OVERDUE (err u8))
(define-constant ERR_COLLATERAL_LOCKED (err u9))
(define-constant ERR_INVALID_INTEREST_RATE (err u10))

(define-data-var loan-id-nonce uint u0)
(define-data-var total-loans-issued uint u0)
(define-data-var total-loans-repaid uint u0)
(define-data-var total-amount-loaned uint u0)
(define-data-var total-amount-repaid uint u0)

(define-map loans
    { loan-id: uint }
    {
        borrower: principal,
        amount: uint,
        collateral-amount: uint,
        interest-rate: uint,
        duration-blocks: uint,
        start-block: uint,
        due-block: uint,
        amount-paid: uint,
        is-active: bool,
        is-defaulted: bool,
        collateral-locked: bool,
        last-payment-block: uint,
    }
)

(define-map borrower-loans
    { borrower: principal }
    { loan-ids: (list 50 uint) }
)

(define-map collateral-deposits
    { borrower: principal }
    { total-collateral: uint }
)

(define-map payment-history
    {
        loan-id: uint,
        payment-id: uint,
    }
    {
        amount: uint,
        block-height: uint,
        payment-type: (string-ascii 20),
    }
)

(define-map loan-payment-counts
    { loan-id: uint }
    { count: uint }
)

(define-read-only (get-loan (loan-id uint))
    (map-get? loans { loan-id: loan-id })
)

(define-read-only (get-borrower-loans (borrower principal))
    (default-to { loan-ids: (list) }
        (map-get? borrower-loans { borrower: borrower })
    )
)

(define-read-only (get-collateral-balance (borrower principal))
    (default-to { total-collateral: u0 }
        (map-get? collateral-deposits { borrower: borrower })
    )
)

(define-read-only (get-loan-payment-count (loan-id uint))
    (default-to { count: u0 } (map-get? loan-payment-counts { loan-id: loan-id }))
)

(define-read-only (get-payment-by-id
        (loan-id uint)
        (payment-id uint)
    )
    (map-get? payment-history {
        loan-id: loan-id,
        payment-id: payment-id,
    })
)

(define-read-only (calculate-interest
        (principal-amount uint)
        (interest-rate uint)
        (blocks-elapsed uint)
    )
    (let ((annual-blocks u52560))
        (/ (* (* principal-amount interest-rate) blocks-elapsed)
            (* annual-blocks u100)
        )
    )
)

(define-read-only (get-outstanding-balance (loan-id uint))
    (match (get-loan loan-id)
        loan-data (let (
                (principal (get amount loan-data))
                (blocks-elapsed (- stacks-block-height (get start-block loan-data)))
                (interest (calculate-interest principal (get interest-rate loan-data)
                    blocks-elapsed
                ))
                (total-owed (+ principal interest))
                (amount-paid (get amount-paid loan-data))
            )
            (ok (if (> total-owed amount-paid)
                (- total-owed amount-paid)
                u0
            ))
        )
        ERR_LOAN_NOT_FOUND
    )
)

(define-read-only (is-loan-overdue (loan-id uint))
    (match (get-loan loan-id)
        loan-data (ok (and (get is-active loan-data) (> stacks-block-height (get due-block loan-data))))
        ERR_LOAN_NOT_FOUND
    )
)

(define-read-only (get-contract-stats)
    {
        total-loans-issued: (var-get total-loans-issued),
        total-loans-repaid: (var-get total-loans-repaid),
        total-amount-loaned: (var-get total-amount-loaned),
        total-amount-repaid: (var-get total-amount-repaid),
        active-loans: (- (var-get total-loans-issued) (var-get total-loans-repaid)),
        current-block: stacks-block-height,
    }
)

(define-public (deposit-collateral (amount uint))
    (let (
            (sender tx-sender)
            (current-balance (get total-collateral (get-collateral-balance sender)))
        )
        (begin
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (try! (stx-transfer? amount sender (as-contract tx-sender)))
            (map-set collateral-deposits { borrower: sender } { total-collateral: (+ current-balance amount) })
            (ok amount)
        )
    )
)

(define-public (withdraw-collateral (amount uint))
    (let (
            (sender tx-sender)
            (current-balance (get total-collateral (get-collateral-balance sender)))
        )
        (begin
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (asserts! (>= current-balance amount) ERR_INSUFFICIENT_COLLATERAL)
            (asserts! (is-ok (check-collateral-availability sender amount))
                ERR_COLLATERAL_LOCKED
            )
            (try! (as-contract (stx-transfer? amount tx-sender sender)))
            (map-set collateral-deposits { borrower: sender } { total-collateral: (- current-balance amount) })
            (ok amount)
        )
    )
)

(define-private (check-collateral-availability
        (borrower principal)
        (amount uint)
    )
    (let (
            (borrower-loan-data (get-borrower-loans borrower))
            (loan-ids (get loan-ids borrower-loan-data))
        )
        (fold check-loan-collateral-requirements loan-ids (ok u0))
    )
)

(define-private (check-loan-collateral-requirements
        (loan-id uint)
        (prev-result (response uint uint))
    )
    (match prev-result
        success (match (get-loan loan-id)
            loan-data (if (get is-active loan-data)
                (ok u0)
                (ok u0)
            )
            (ok u0)
        )
        error
        prev-result
    )
)

(define-public (create-loan
        (amount uint)
        (collateral-amount uint)
        (interest-rate uint)
        (duration-blocks uint)
    )
    (let (
            (loan-id (+ (var-get loan-id-nonce) u1))
            (sender tx-sender)
            (current-collateral (get total-collateral (get-collateral-balance sender)))
            (start-block stacks-block-height)
            (due-block (+ start-block duration-blocks))
        )
        (begin
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)
            (asserts! (>= current-collateral collateral-amount)
                ERR_INSUFFICIENT_COLLATERAL
            )
            (asserts! (> duration-blocks u0) ERR_INVALID_DURATION)
            (asserts! (<= interest-rate u50) ERR_INVALID_INTEREST_RATE)

            (map-set loans { loan-id: loan-id } {
                borrower: sender,
                amount: amount,
                collateral-amount: collateral-amount,
                interest-rate: interest-rate,
                duration-blocks: duration-blocks,
                start-block: start-block,
                due-block: due-block,
                amount-paid: u0,
                is-active: true,
                is-defaulted: false,
                collateral-locked: true,
                last-payment-block: u0,
            })

            (let ((current-loans (get loan-ids (get-borrower-loans sender))))
                (map-set borrower-loans { borrower: sender } { loan-ids: (unwrap-panic (as-max-len? (append current-loans loan-id) u50)) })
            )

            (var-set loan-id-nonce loan-id)
            (var-set total-loans-issued (+ (var-get total-loans-issued) u1))
            (var-set total-amount-loaned (+ (var-get total-amount-loaned) amount))

            (try! (as-contract (stx-transfer? amount tx-sender sender)))
            (ok loan-id)
        )
    )
)

(define-public (make-payment
        (loan-id uint)
        (payment-amount uint)
    )
    (let (
            (sender tx-sender)
            (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
            (outstanding-balance (unwrap! (get-outstanding-balance loan-id) ERR_LOAN_NOT_FOUND))
            (payment-count (default-to { count: u0 }
                (map-get? loan-payment-counts { loan-id: loan-id })
            ))
        )
        (begin
            (asserts! (is-eq sender (get borrower loan-data)) ERR_UNAUTHORIZED)
            (asserts! (get is-active loan-data) ERR_LOAN_NOT_ACTIVE)
            (asserts! (> payment-amount u0) ERR_INVALID_AMOUNT)
            (asserts! (<= payment-amount outstanding-balance) ERR_INVALID_AMOUNT)

            (try! (stx-transfer? payment-amount sender (as-contract tx-sender)))

            (let ((new-amount-paid (+ (get amount-paid loan-data) payment-amount)))
                (map-set loans { loan-id: loan-id }
                    (merge loan-data {
                        amount-paid: new-amount-paid,
                        last-payment-block: stacks-block-height,
                        is-active: (> outstanding-balance payment-amount),
                    })
                )

                (map-set payment-history {
                    loan-id: loan-id,
                    payment-id: (get count payment-count),
                } {
                    amount: payment-amount,
                    block-height: stacks-block-height,
                    payment-type: "regular",
                })

                (map-set loan-payment-counts { loan-id: loan-id } { count: (+ (get count payment-count) u1) })

                (var-set total-amount-repaid
                    (+ (var-get total-amount-repaid) payment-amount)
                )

                (if (is-eq outstanding-balance payment-amount)
                    (begin
                        (var-set total-loans-repaid
                            (+ (var-get total-loans-repaid) u1)
                        )
                        (map-set loans { loan-id: loan-id }
                            (merge loan-data {
                                amount-paid: new-amount-paid,
                                last-payment-block: stacks-block-height,
                                is-active: false,
                                collateral-locked: false,
                            })
                        )
                        (ok {
                            payment-amount: payment-amount,
                            loan-completed: true,
                        })
                    )
                    (ok {
                        payment-amount: payment-amount,
                        loan-completed: false,
                    })
                )
            )
        )
    )
)

(define-public (default-loan (loan-id uint))
    (let (
            (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
            (is-overdue (unwrap! (is-loan-overdue loan-id) ERR_LOAN_NOT_FOUND))
        )
        (begin
            (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
            (asserts! (get is-active loan-data) ERR_LOAN_NOT_ACTIVE)
            (asserts! is-overdue ERR_PAYMENT_OVERDUE)

            (map-set loans { loan-id: loan-id }
                (merge loan-data {
                    is-active: false,
                    is-defaulted: true,
                    collateral-locked: false,
                })
            )

            (let ((payment-count (default-to { count: u0 }
                    (map-get? loan-payment-counts { loan-id: loan-id })
                )))
                (map-set payment-history {
                    loan-id: loan-id,
                    payment-id: (get count payment-count),
                } {
                    amount: u0,
                    block-height: stacks-block-height,
                    payment-type: "default",
                })

                (map-set loan-payment-counts { loan-id: loan-id } { count: (+ (get count payment-count) u1) })
            )

            (ok loan-id)
        )
    )
)
