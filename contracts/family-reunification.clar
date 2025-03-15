;; Family Reunification Contract
;; Helps reconnect separated family members

(define-data-var admin principal tx-sender)

;; Map of family relationships
(define-map family-relationships
  { identity-id-1: uint, identity-id-2: uint }
  {
    relationship-type: (string-ascii 50), ;; "parent-child", "spouse", "sibling"
    verified: bool,
    verification-date: uint,
    verifier: principal
  }
)

;; Map of reunion requests
(define-map reunion-requests
  uint
  {
    requester-id: uint,
    sought-person-name: (string-ascii 100),
    sought-person-id: uint, ;; 0 if unknown
    last-known-location: (string-ascii 100),
    last-seen-date: (string-ascii 10),
    additional-info: (string-ascii 500),
    status: (string-ascii 20), ;; "open", "in-progress", "matched", "closed"
    request-date: uint,
    privacy-level: uint, ;; 1: public, 2: limited, 3: private
    handling-agency: principal
  }
)

;; Map of potential matches
(define-map potential-matches
  { request-id: uint, identity-id: uint }
  {
    match-score: uint, ;; 0-100
    match-date: uint,
    match-notes: (string-ascii 200),
    status: (string-ascii 20), ;; "potential", "confirmed", "rejected"
    confirmed-by: principal
  }
)

;; Map of reunion agencies
(define-map reunion-agencies
  principal
  {
    name: (string-ascii 100),
    agency-type: (string-ascii 50), ;; "NGO", "government", "UN"
    authorized: bool,
    authorization-date: uint
  }
)

;; Map to track identity details (simplified from identity-verification)
(define-map identities
  uint
  {
    person: principal,
    full-name: (string-ascii 100),
    status: (string-ascii 20)
  }
)

;; Counter for request IDs
(define-data-var next-request-id uint u1)

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
  (full-name (string-ascii 100))
  (status (string-ascii 20))
)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))
    (map-set identities identity-id {
      person: person,
      full-name: full-name,
      status: status
    })
    (ok true)
  )
)

;; Register a reunion agency
(define-public (register-agency (name (string-ascii 100)) (agency-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set reunion-agencies
      tx-sender
      {
        name: name,
        agency-type: agency-type,
        authorized: true,
        authorization-date: block-height
      }
    )

    (ok true)
  )
)

;; Authorize an agency
(define-public (authorize-agency (agency principal))
  (let (
    (agency-data (unwrap! (map-get? reunion-agencies agency) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set reunion-agencies
      agency
      (merge agency-data {
        authorized: true,
        authorization-date: block-height
      })
    )

    (ok true)
  )
)

;; Revoke agency authorization
(define-public (revoke-agency (agency principal))
  (let (
    (agency-data (unwrap! (map-get? reunion-agencies agency) (err u3)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))

    (map-set reunion-agencies
      agency
      (merge agency-data { authorized: false })
    )

    (ok true)
  )
)

;; Record a family relationship
(define-public (record-relationship
  (identity-id-1 uint)
  (identity-id-2 uint)
  (relationship-type (string-ascii 50))
)
  (let (
    (agency-data (unwrap! (map-get? reunion-agencies tx-sender) (err u3)))
    (identity-1 (unwrap! (map-get? identities identity-id-1) (err u4)))
    (identity-2 (unwrap! (map-get? identities identity-id-2) (err u4)))
  )
    ;; Only authorized agencies can record relationships
    (asserts! (get authorized agency-data) (err u5))
    ;; Both identities must be active
    (asserts! (is-eq (get status identity-1) "active") (err u6))
    (asserts! (is-eq (get status identity-2) "active") (err u6))
    ;; Cannot record relationship with self
    (asserts! (not (is-eq identity-id-1 identity-id-2)) (err u7))

    ;; Record the relationship
    (map-set family-relationships
      { identity-id-1: identity-id-1, identity-id-2: identity-id-2 }
      {
        relationship-type: relationship-type,
        verified: false,
        verification-date: u0,
        verifier: tx-sender
      }
    )

    ;; Also record the inverse relationship for easy lookup
    (map-set family-relationships
      { identity-id-1: identity-id-2, identity-id-2: identity-id-1 }
      {
        relationship-type: relationship-type,
        verified: false,
        verification-date: u0,
        verifier: tx-sender
      }
    )

    (ok true)
  )
)

;; Verify a family relationship
(define-public (verify-relationship (identity-id-1 uint) (identity-id-2 uint))
  (let (
    (agency-data (unwrap! (map-get? reunion-agencies tx-sender) (err u3)))
    (relationship (unwrap! (map-get? family-relationships { identity-id-1: identity-id-1, identity-id-2: identity-id-2 }) (err u8)))
  )
    ;; Only authorized agencies can verify relationships
    (asserts! (get authorized agency-data) (err u5))

    ;; Update the relationship
    (map-set family-relationships
      { identity-id-1: identity-id-1, identity-id-2: identity-id-2 }
      (merge relationship {
        verified: true,
        verification-date: block-height,
        verifier: tx-sender
      })
    )

    ;; Also update the inverse relationship
    (map-set family-relationships
      { identity-id-1: identity-id-2, identity-id-2: identity-id-1 }
      (merge relationship {
        verified: true,
        verification-date: block-height,
        verifier: tx-sender
      })
    )

    (ok true)
  )
)

;; Create a reunion request
(define-public (create-reunion-request
  (requester-id uint)
  (sought-person-name (string-ascii 100))
  (sought-person-id uint) ;; 0 if unknown
  (last-known-location (string-ascii 100))
  (last-seen-date (string-ascii 10))
  (additional-info (string-ascii 500))
  (privacy-level uint)
)
  (let (
    (request-id (var-get next-request-id))
    (agency-data (unwrap! (map-get? reunion-agencies tx-sender) (err u3)))
    (requester (unwrap! (map-get? identities requester-id) (err u4)))
  )
    ;; Only authorized agencies can create requests
    (asserts! (get authorized agency-data) (err u5))
    ;; Requester identity must be active
    (asserts! (is-eq (get status requester) "active") (err u6))
    ;; Privacy level must be valid (1-3)
    (asserts! (and (>= privacy-level u1) (<= privacy-level u3)) (err u9))

    ;; Create the request
    (map-set reunion-requests
      request-id
      {
        requester-id: requester-id,
        sought-person-name: sought-person-name,
        sought-person-id: sought-person-id,
        last-known-location: last-known-location,
        last-seen-date: last-seen-date,
        additional-info: additional-info,
        status: "open",
        request-date: block-height,
        privacy-level: privacy-level,
        handling-agency: tx-sender
      }
    )

    ;; Increment the request ID counter
    (var-set next-request-id (+ request-id u1))

    (ok request-id)
  )
)

;; Update reunion request status
(define-public (update-request-status (request-id uint) (status (string-ascii 20)))
  (let (
    (request (unwrap! (map-get? reunion-requests request-id) (err u10)))
  )
    ;; Only the handling agency can update status
    (asserts! (is-eq tx-sender (get handling-agency request)) (err u11))

    ;; Update the request
    (map-set reunion-requests
      request-id
      (merge request { status: status })
    )

    (ok true)
  )
)

;; Record a potential match
(define-public (record-potential-match
  (request-id uint)
  (identity-id uint)
  (match-score uint)
  (match-notes (string-ascii 200))
)
  (let (
    (request (unwrap! (map-get? reunion-requests request-id) (err u10)))
    (agency-data (unwrap! (map-get? reunion-agencies tx-sender) (err u3)))
    (identity (unwrap! (map-get? identities identity-id) (err u4)))
  )
    ;; Only authorized agencies can record matches
    (asserts! (get authorized agency-data) (err u5))
    ;; Identity must be active
    (asserts! (is-eq (get status identity) "active") (err u6))
    ;; Match score must be valid (0-100)
    (asserts! (<= match-score u100) (err u12))

    ;; Record the match
    (map-set potential-matches
      { request-id: request-id, identity-id: identity-id }
      {
        match-score: match-score,
        match-date: block-height,
        match-notes: match-notes,
        status: "potential",
        confirmed-by: tx-sender
      }
    )

    (ok true)
  )
)

;; Confirm a match
(define-public (confirm-match (request-id uint) (identity-id uint))
  (let (
    (request (unwrap! (map-get? reunion-requests request-id) (err u10)))
    (match (unwrap! (map-get? potential-matches { request-id: request-id, identity-id: identity-id }) (err u13)))
  )
    ;; Only the handling agency can confirm matches
    (asserts! (is-eq tx-sender (get handling-agency request)) (err u11))

    ;; Update the match
    (map-set potential-matches
      { request-id: request-id, identity-id: identity-id }
      (merge match {
        status: "confirmed",
        confirmed-by: tx-sender
      })
    )

    ;; Update the request status
    (map-set reunion-requests
      request-id
      (merge request {
        status: "matched",
        sought-person-id: identity-id
      })
    )

    (ok true)
  )
)

;; Get relationship details
(define-read-only (get-relationship (identity-id-1 uint) (identity-id-2 uint))
  (map-get? family-relationships { identity-id-1: identity-id-1, identity-id-2: identity-id-2 })
)

;; Get reunion request details
(define-read-only (get-reunion-request (request-id uint))
  (map-get? reunion-requests request-id)
)

;; Get potential match details
(define-read-only (get-potential-match (request-id uint) (identity-id uint))
  (map-get? potential-matches { request-id: request-id, identity-id: identity-id })
)

;; Get agency details
(define-read-only (get-agency (agency principal))
  (map-get? reunion-agencies agency)
)

;; Check if two people are related
(define-read-only (are-related (identity-id-1 uint) (identity-id-2 uint))
  (is-some (map-get? family-relationships { identity-id-1: identity-id-1, identity-id-2: identity-id-2 }))
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u2))
    (var-set admin new-admin)
    (ok true)
  )
)
