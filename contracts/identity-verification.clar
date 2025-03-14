;; Identity Verification Contract
;; Provides secure digital IDs for displaced persons

(define-data-var admin principal tx-sender)

;; Map of identity IDs to identity details
(define-map identities
  uint
  {
    person: principal,
    full-name: (string-ascii 100),
    birth-date: (string-ascii 10),
    nationality: (string-ascii 50),
    biometric-hash: (string-ascii 64),
    status: (string-ascii 20), ;; "active", "expired", "suspended"
    verification-level: uint, ;; 1: basic, 2: verified, 3: fully verified
    issue-date: uint,
    expiry-date: uint,
    last-updated: uint
  }
)

;; Map of verifier organizations
(define-map verifiers
  principal
  {
    name: (string-ascii 100),
    organization-type: (string-ascii 50), ;; "NGO", "government", "UN"
    authorized: bool,
    authorization-date: uint
  }
)

;; Map of verification records
(define-map verification-records
  { identity-id: uint, verifier: principal }
  {
    verification-date: uint,
    verification-level: uint,
    verification-notes: (string-ascii 200)
  }
)

;; Counter for identity IDs
(define-data-var next-identity-id uint u1)

;; Initialize the contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u1))
    (ok true)
  )
)

;; Register a verifier organization
(define-public (register-verifier (name (string-ascii 100)) (organization-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set verifiers
      tx-sender
      {
        name: name,
        organization-type: organization-type,
        authorized: true,
        authorization-date: block-height
      }
    )

    (ok true)
  )
)

;; Authorize a verifier
(define-public (authorize-verifier (verifier principal))
  (let (
    (verifier-data (unwrap! (map-get? verifiers verifier) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set verifiers
      verifier
      (merge verifier-data {
        authorized: true,
        authorization-date: block-height
      })
    )

    (ok true)
  )
)

;; Revoke verifier authorization
(define-public (revoke-verifier (verifier principal))
  (let (
    (verifier-data (unwrap! (map-get? verifiers verifier) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set verifiers
      verifier
      (merge verifier-data { authorized: false })
    )

    (ok true)
  )
)

;; Register a new identity
(define-public (register-identity
  (person principal)
  (full-name (string-ascii 100))
  (birth-date (string-ascii 10))
  (nationality (string-ascii 50))
  (biometric-hash (string-ascii 64))
  (expiry-days uint)
)
  (let (
    (identity-id (var-get next-identity-id))
    (verifier-data (unwrap! (map-get? verifiers tx-sender) (err u3)))
    (expiry-date (+ block-height (* expiry-days u144))) ;; ~144 blocks per day
  )
    ;; Only authorized verifiers can register identities
    (asserts! (get authorized verifier-data) (err u4))

    ;; Create the identity
    (map-set identities
      identity-id
      {
        person: person,
        full-name: full-name,
        birth-date: birth-date,
        nationality: nationality,
        biometric-hash: biometric-hash,
        status: "active",
        verification-level: u1,
        issue-date: block-height,
        expiry-date: expiry-date,
        last-updated: block-height
      }
    )

    ;; Create verification record
    (map-set verification-records
      { identity-id: identity-id, verifier: tx-sender }
      {
        verification-date: block-height,
        verification-level: u1,
        verification-notes: "Initial registration"
      }
    )

    ;; Increment the identity ID counter
    (var-set next-identity-id (+ identity-id u1))

    (ok identity-id)
  )
)

;; Verify an identity (increase verification level)
(define-public (verify-identity
  (identity-id uint)
  (verification-level uint)
  (verification-notes (string-ascii 200))
)
  (let (
    (identity (unwrap! (map-get? identities identity-id) (err u5)))
    (verifier-data (unwrap! (map-get? verifiers tx-sender) (err u3)))
  )
    ;; Only authorized verifiers can verify identities
    (asserts! (get authorized verifier-data) (err u4))
    ;; Verification level must be higher than current level
    (asserts! (> verification-level (get verification-level identity)) (err u6))
    ;; Verification level must be valid (1-3)
    (asserts! (<= verification-level u3) (err u7))

    ;; Update the identity
    (map-set identities
      identity-id
      (merge identity {
        verification-level: verification-level,
        last-updated: block-height
      })
    )

    ;; Create verification record
    (map-set verification-records
      { identity-id: identity-id, verifier: tx-sender }
      {
        verification-date: block-height,
        verification-level: verification-level,
        verification-notes: verification-notes
      }
    )

    (ok true)
  )
)

;; Update identity status
(define-public (update-identity-status (identity-id uint) (status (string-ascii 20)))
  (let (
    (identity (unwrap! (map-get? identities identity-id) (err u5)))
    (verifier-data (unwrap! (map-get? verifiers tx-sender) (err u3)))
  )
    ;; Only authorized verifiers can update identity status
    (asserts! (get authorized verifier-data) (err u4))

    ;; Update the identity
    (map-set identities
      identity-id
      (merge identity {
        status: status,
        last-updated: block-height
      })
    )

    (ok true)
  )
)

;; Renew an identity
(define-public (renew-identity (identity-id uint) (expiry-days uint))
  (let (
    (identity (unwrap! (map-get? identities identity-id) (err u5)))
    (verifier-data (unwrap! (map-get? verifiers tx-sender) (err u3)))
    (new-expiry-date (+ block-height (* expiry-days u144))) ;; ~144 blocks per day
  )
    ;; Only authorized verifiers can renew identities
    (asserts! (get authorized verifier-data) (err u4))

    ;; Update the identity
    (map-set identities
      identity-id
      (merge identity {
        status: "active",
        expiry-date: new-expiry-date,
        last-updated: block-height
      })
    )

    (ok true)
  )
)

;; Get identity details (public function for verification)
(define-read-only (get-identity (identity-id uint))
  (map-get? identities identity-id)
)

;; Get verification record
(define-read-only (get-verification-record (identity-id uint) (verifier principal))
  (map-get? verification-records { identity-id: identity-id, verifier: verifier })
)

;; Check if an identity is valid
(define-read-only (is-identity-valid (identity-id uint))
  (match (map-get? identities identity-id)
    identity (and (is-eq (get status identity) "active")
                 (>= (get expiry-date identity) block-height))
    false)
)

;; Get verification level
(define-read-only (get-verification-level (identity-id uint))
  (match (map-get? identities identity-id)
    identity (get verification-level identity)
    u0)
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))
    (var-set admin new-admin)
    (ok true)
  )
)
