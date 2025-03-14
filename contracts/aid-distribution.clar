;; Aid Distribution Contract
;; Manages fair allocation of resources

(define-data-var admin principal tx-sender)

;; Map of aid distribution events
(define-map aid-distributions
  uint
  {
    aid-type: (string-ascii 50), ;; "food", "shelter", "medical", "cash", "supplies"
    location: (string-ascii 100),
    start-date: uint,
    end-date: uint,
    total-allocation: uint,
    distributed-amount: uint,
    status: (string-ascii 20), ;; "planned", "active", "completed", "cancelled"
    organizer: principal
  }
)

;; Map of aid receipts
(define-map aid-receipts
  { distribution-id: uint, recipient-id: uint }
  {
    amount: uint,
    receipt-date: uint,
    distributor: principal,
    notes: (string-ascii 200)
  }
)

;; Map of aid distributors
(define-map distributors
  principal
  {
    name: (string-ascii 100),
    organization: (string-ascii 100),
    authorized: bool,
    authorization-date: uint
  }
)

;; Map to track identity details (simplified from identity-verification)
(define-map identities
  uint
  {
    person: principal,
    status: (string-ascii 20),
    verification-level: uint
  }
)

;; Counter for distribution IDs
(define-data-var next-distribution-id uint u1)

;; Initialize the contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u1))
    (ok true)
  )
)

;; Set identity details (admin function to sync with identity-verification)
(define-public (set-identity-details
  (identity-id uint)
  (person principal)
  (status (string-ascii 20))
  (verification-level uint)
)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))
    (map-set identities identity-id {
      person: person,
      status: status,
      verification-level: verification-level
    })
    (ok true)
  )
)

;; Register a distributor
(define-public (register-distributor (name (string-ascii 100)) (organization (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set distributors
      tx-sender
      {
        name: name,
        organization: organization,
        authorized: true,
        authorization-date: block-height
      }
    )

    (ok true)
  )
)

;; Authorize a distributor
(define-public (authorize-distributor (distributor principal))
  (let (
    (distributor-data (unwrap! (map-get? distributors distributor) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set distributors
      distributor
      (merge distributor-data {
        authorized: true,
        authorization-date: block-height
      })
    )

    (ok true)
  )
)

;; Revoke distributor authorization
(define-public (revoke-distributor (distributor principal))
  (let (
    (distributor-data (unwrap! (map-get? distributors distributor) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set distributors
      distributor
      (merge distributor-data { authorized: false })
    )

    (ok true)
  )
)

;; Create a new aid distribution event
(define-public (create-aid-distribution
  (aid-type (string-ascii 50))
  (location (string-ascii 100))
  (start-date uint)
  (end-date uint)
  (total-allocation uint)
)
  (let (
    (distribution-id (var-get next-distribution-id))
    (distributor-data (unwrap! (map-get? distributors tx-sender) (err u3)))
  )
    ;; Only authorized distributors can create distributions
    (asserts! (get authorized distributor-data) (err u4))
    ;; End date must be after start date
    (asserts! (> end-date start-date) (err u5))
    ;; Total allocation must be positive
    (asserts! (> total-allocation u0) (err u6))

    ;; Create the distribution
    (map-set aid-distributions
      distribution-id
      {
        aid-type: aid-type,
        location: location,
        start-date: start-date,
        end-date: end-date,
        total-allocation: total-allocation,
        distributed-amount: u0,
        status: "planned",
        organizer: tx-sender
      }
    )

    ;; Increment the distribution ID counter
    (var-set next-distribution-id (+ distribution-id u1))

    (ok distribution-id)
  )
)

;; Update aid distribution status
(define-public (update-distribution-status (distribution-id uint) (status (string-ascii 20)))
  (let (
    (distribution (unwrap! (map-get? aid-distributions distribution-id) (err u7)))
  )
    ;; Only the organizer or admin can update status
    (asserts! (or (is-eq tx-sender (get organizer distribution))
                 (is-eq tx-sender (var-get admin)))
             (err u8))

    ;; Update the distribution
    (map-set aid-distributions
      distribution-id
      (merge distribution { status: status })
    )

    (ok true)
  )
)

;; Record aid distribution to a recipient
(define-public (distribute-aid
  (distribution-id uint)
  (recipient-id uint)
  (amount uint)
  (notes (string-ascii 200))
)
  (let (
    (distribution (unwrap! (map-get? aid-distributions distribution-id) (err u7)))
    (distributor-data (unwrap! (map-get? distributors tx-sender) (err u3)))
    (identity (unwrap! (map-get? identities recipient-id) (err u9)))
    (new-distributed-amount (+ (get distributed-amount distribution) amount))
    (existing-receipt (map-get? aid-receipts { distribution-id: distribution-id, recipient-id: recipient-id }))
  )
    ;; Only authorized distributors can distribute aid
    (asserts! (get authorized distributor-data) (err u4))
    ;; Distribution must be active
    (asserts! (is-eq (get status distribution) "active") (err u10))
    ;; Identity must be active
    (asserts! (is-eq (get status identity) "active") (err u11))
    ;; Identity must have minimum verification level
    (asserts! (>= (get verification-level identity) u1) (err u12))
    ;; Cannot exceed total allocation
    (asserts! (<= new-distributed-amount (get total-allocation distribution)) (err u13))
    ;; Recipient should not have already received aid from this distribution
    (asserts! (is-none existing-receipt) (err u14))

    ;; Record the aid receipt
    (map-set aid-receipts
      { distribution-id: distribution-id, recipient-id: recipient-id }
      {
        amount: amount,
        receipt-date: block-height,
        distributor: tx-sender,
        notes: notes
      }
    )

    ;; Update the distributed amount
    (map-set aid-distributions
      distribution-id
      (merge distribution { distributed-amount: new-distributed-amount })
    )

    (ok true)
  )
)

;; Get aid distribution details
(define-read-only (get-aid-distribution (distribution-id uint))
  (map-get? aid-distributions distribution-id)
)

;; Get aid receipt details
(define-read-only (get-aid-receipt (distribution-id uint) (recipient-id uint))
  (map-get? aid-receipts { distribution-id: distribution-id, recipient-id: recipient-id })
)

;; Check if a recipient has received aid from a distribution
(define-read-only (has-received-aid (distribution-id uint) (recipient-id uint))
  (is-some (map-get? aid-receipts { distribution-id: distribution-id, recipient-id: recipient-id }))
)

;; Get distributor details
(define-read-only (get-distributor (distributor principal))
  (map-get? distributors distributor)
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))
    (var-set admin new-admin)
    (ok true)
  )
)
