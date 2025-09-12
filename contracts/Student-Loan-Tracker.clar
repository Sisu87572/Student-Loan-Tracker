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
(define-constant ERR_EXTENSION_LIMIT_REACHED (err u11))
(define-constant ERR_GRACE_PERIOD_EXPIRED (err u12))
(define-constant ERR_INSUFFICIENT_EXTENSION_COLLATERAL (err u13))
(define-constant ERR_LOAN_NOT_LIQUIDATABLE (err u14))
(define-constant ERR_LOAN_ALREADY_LIQUIDATED (err u15))

(define-data-var loan-id-nonce uint u0)
(define-data-var total-loans-issued uint u0)
(define-data-var total-loans-repaid uint u0)
(define-data-var total-amount-loaned uint u0)
(define-data-var total-amount-repaid uint u0)
(define-data-var total-extensions-granted uint u0)
(define-data-var extension-fee-rate uint u5)
(define-data-var liquidation-threshold-blocks uint u2880)
(define-data-var liquidation-penalty-rate uint u10)
(define-data-var total-loans-liquidated uint u0)

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
        extensions-used: uint,
        grace-period-end: uint,
        extension-fee-paid: uint,
        is-liquidated: bool,
        liquidated-block: uint,
        liquidation-penalty: uint,
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

(define-map liquidation-history
    { loan-id: uint }
    {
        liquidator: principal,
        liquidation-block: uint,
        total-debt: uint,
        collateral-seized: uint,
        collateral-returned: uint,
        penalty-amount: uint,
    }
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
        loan-data (let (
                (is-active (get is-active loan-data))
                (past-due (> stacks-block-height (get due-block loan-data)))
                (in-grace (unwrap-panic (is-in-grace-period loan-id)))
            )
            (ok (and
                is-active
                past-due
                (not in-grace)
            ))
        )
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
        total-extensions-granted: (var-get total-extensions-granted),
        total-loans-liquidated: (var-get total-loans-liquidated),
        extension-fee-rate: (var-get extension-fee-rate),
        liquidation-threshold-blocks: (var-get liquidation-threshold-blocks),
        liquidation-penalty-rate: (var-get liquidation-penalty-rate),
        current-block: stacks-block-height,
    }
)

(define-read-only (get-liquidation-history (loan-id uint))
    (map-get? liquidation-history { loan-id: loan-id })
)

(define-read-only (is-loan-liquidatable (loan-id uint))
    (match (get-loan loan-id)
        loan-data (let (
                (is-active (get is-active loan-data))
                (is-liquidated (get is-liquidated loan-data))
                (blocks-overdue (- stacks-block-height (get due-block loan-data)))
                (threshold (var-get liquidation-threshold-blocks))
                (in-grace (unwrap-panic (is-in-grace-period loan-id)))
            )
            (ok (and
                is-active
                (not is-liquidated)
                (> blocks-overdue threshold)
                (not in-grace)
            ))
        )
        ERR_LOAN_NOT_FOUND
    )
)

(define-read-only (calculate-liquidation-amounts (loan-id uint))
    (match (get-loan loan-id)
        loan-data (let (
                (outstanding (unwrap-panic (get-outstanding-balance loan-id)))
                (collateral (get collateral-amount loan-data))
                (penalty-rate (var-get liquidation-penalty-rate))
                (penalty (/ (* outstanding penalty-rate) u100))
                (total-debt (+ outstanding penalty))
                (collateral-seized (if (> collateral total-debt) total-debt collateral))
                (collateral-returned (if (> collateral total-debt) (- collateral total-debt) u0))
            )
            (ok {
                outstanding-balance: outstanding,
                penalty-amount: penalty,
                total-debt: total-debt,
                collateral-seized: collateral-seized,
                collateral-returned: collateral-returned,
            })
        )
        ERR_LOAN_NOT_FOUND
    )
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
                extensions-used: u0,
                grace-period-end: u0,
                extension-fee-paid: u0,
                is-liquidated: false,
                liquidated-block: u0,
                liquidation-penalty: u0,
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

(define-read-only (get-extension-fee (loan-id uint))
    (match (get-loan loan-id)
        loan-data (let (
                (principal (get amount loan-data))
                (fee-rate (var-get extension-fee-rate))
            )
            (ok (/ (* principal fee-rate) u100))
        )
        ERR_LOAN_NOT_FOUND
    )
)

(define-read-only (is-in-grace-period (loan-id uint))
    (match (get-loan loan-id)
        loan-data (let ((grace-end (get grace-period-end loan-data)))
            (ok (and (> grace-end u0) (<= stacks-block-height grace-end)))
        )
        ERR_LOAN_NOT_FOUND
    )
)

(define-public (request-loan-extension
        (loan-id uint)
        (extension-blocks uint)
    )
    (let (
            (sender tx-sender)
            (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
            (extension-fee (unwrap! (get-extension-fee loan-id) ERR_LOAN_NOT_FOUND))
            (current-collateral (get total-collateral (get-collateral-balance sender)))
            (required-collateral (* (get collateral-amount loan-data) u125))
            (max-extensions u2)
        )
        (begin
            (asserts! (is-eq sender (get borrower loan-data)) ERR_UNAUTHORIZED)
            (asserts! (get is-active loan-data) ERR_LOAN_NOT_ACTIVE)
            (asserts! (< (get extensions-used loan-data) max-extensions)
                ERR_EXTENSION_LIMIT_REACHED
            )
            (asserts! (> extension-blocks u0) ERR_INVALID_DURATION)
            (asserts! (>= (* current-collateral u100) required-collateral)
                ERR_INSUFFICIENT_EXTENSION_COLLATERAL
            )

            (try! (stx-transfer? extension-fee sender (as-contract tx-sender)))

            (let (
                    (new-due-block (+ (get due-block loan-data) extension-blocks))
                    (grace-period-blocks u1440)
                    (new-grace-end (+ (get due-block loan-data) grace-period-blocks))
                )
                (map-set loans { loan-id: loan-id }
                    (merge loan-data {
                        due-block: new-due-block,
                        extensions-used: (+ (get extensions-used loan-data) u1),
                        grace-period-end: new-grace-end,
                        extension-fee-paid: (+ (get extension-fee-paid loan-data) extension-fee),
                    })
                )

                (let ((payment-count (default-to { count: u0 }
                        (map-get? loan-payment-counts { loan-id: loan-id })
                    )))
                    (map-set payment-history {
                        loan-id: loan-id,
                        payment-id: (get count payment-count),
                    } {
                        amount: extension-fee,
                        block-height: stacks-block-height,
                        payment-type: "extension-fee",
                    })

                    (map-set loan-payment-counts { loan-id: loan-id } { count: (+ (get count payment-count) u1) })
                )

                (var-set total-extensions-granted
                    (+ (var-get total-extensions-granted) u1)
                )
                (ok {
                    extension-blocks: extension-blocks,
                    fee-paid: extension-fee,
                    new-due-block: new-due-block,
                    extensions-remaining: (- max-extensions (get extensions-used loan-data) u1),
                })
            )
        )
    )
)

(define-public (update-extension-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u20) ERR_INVALID_INTEREST_RATE)
        (var-set extension-fee-rate new-rate)
        (ok new-rate)
    )
)

(define-public (update-liquidation-parameters
        (threshold-blocks uint)
        (penalty-rate uint)
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> threshold-blocks u0) ERR_INVALID_DURATION)
        (asserts! (<= penalty-rate u50) ERR_INVALID_INTEREST_RATE)
        (var-set liquidation-threshold-blocks threshold-blocks)
        (var-set liquidation-penalty-rate penalty-rate)
        (ok { threshold-blocks: threshold-blocks, penalty-rate: penalty-rate })
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

(define-public (liquidate-loan (loan-id uint))
    (let (
            (liquidator tx-sender)
            (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
            (liquidatable (unwrap! (is-loan-liquidatable loan-id) ERR_LOAN_NOT_FOUND))
            (amounts (unwrap! (calculate-liquidation-amounts loan-id) ERR_LOAN_NOT_FOUND))
            (borrower (get borrower loan-data))
            (current-collateral (get total-collateral (get-collateral-balance borrower)))
        )
        (begin
            (asserts! liquidatable ERR_LOAN_NOT_LIQUIDATABLE)
            (asserts! (not (get is-liquidated loan-data)) ERR_LOAN_ALREADY_LIQUIDATED)
            (asserts! (get is-active loan-data) ERR_LOAN_NOT_ACTIVE)

            (map-set loans { loan-id: loan-id }
                (merge loan-data {
                    is-active: false,
                    is-liquidated: true,
                    liquidated-block: stacks-block-height,
                    liquidation-penalty: (get penalty-amount amounts),
                })
            )

            (map-set liquidation-history { loan-id: loan-id } {
                liquidator: liquidator,
                liquidation-block: stacks-block-height,
                total-debt: (get total-debt amounts),
                collateral-seized: (get collateral-seized amounts),
                collateral-returned: (get collateral-returned amounts),
                penalty-amount: (get penalty-amount amounts),
            })

            (if (> (get collateral-returned amounts) u0)
                (begin
                    (try! (as-contract (stx-transfer? (get collateral-returned amounts) tx-sender borrower)))
                    (map-set collateral-deposits { borrower: borrower } { total-collateral: (- current-collateral (get collateral-amount loan-data)) })
                )
                (map-set collateral-deposits { borrower: borrower } { total-collateral: (- current-collateral (get collateral-amount loan-data)) })
            )

            (let ((payment-count (default-to { count: u0 }
                    (map-get? loan-payment-counts { loan-id: loan-id })
                )))
                (map-set payment-history {
                    loan-id: loan-id,
                    payment-id: (get count payment-count),
                } {
                    amount: (get collateral-seized amounts),
                    block-height: stacks-block-height,
                    payment-type: "liquidation",
                })

                (map-set loan-payment-counts { loan-id: loan-id } { count: (+ (get count payment-count) u1) })
            )

            (var-set total-loans-liquidated
                (+ (var-get total-loans-liquidated) u1)
            )

            (ok {
                loan-id: loan-id,
                collateral-seized: (get collateral-seized amounts),
                collateral-returned: (get collateral-returned amounts),
                penalty-applied: (get penalty-amount amounts),
                liquidator: liquidator,
            })
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
