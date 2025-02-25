;; proposal-manager.clar
;; Manages DAO proposals and voting process

;; Import the local SIP-010 trait
(use-trait sip-010-trait .sip-010-trait.sip-010-trait)

;; Constants and Errors
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-invalid-proposal (err u201))
(define-constant err-proposal-active (err u202))
(define-constant err-proposal-ended (err u203))
(define-constant err-already-voted (err u204))
(define-constant err-insufficient-voting-power (err u205))
(define-constant err-voting-delay (err u206))
(define-constant err-invalid-quorum (err u207))
(define-constant err-execution-failed (err u208))
(define-constant err-not-executable (err u209))
(define-constant err-already-executed (err u210))
(define-constant err-invalid-title (err u211))
(define-constant err-invalid-description (err u212))
(define-constant err-invalid-execution-delay (err u213))
(define-constant err-invalid-voting-token (err u214))
(define-constant err-invalid-vote-amount (err u215))
(define-constant err-unauthorized-token (err u216))

;; Data Variables
(define-data-var proposal-count uint u0)
(define-data-var min-proposal-duration uint u14400) ;; Minimum 100 blocks (~14400 seconds)
(define-data-var quorum-threshold uint u200000) ;; 20% of total supply with 6 decimals
(define-data-var vote-threshold uint u500000) ;; 50% threshold for proposal to pass
(define-data-var max-execution-delay uint u432000) ;; Maximum 3 days (in seconds)

;; Proposal status constants
(define-constant proposal-status-active u1)
(define-constant proposal-status-succeeded u2)
(define-constant proposal-status-failed u3)
(define-constant proposal-status-executed u4)

;; Token whitelist for allowed governance tokens
(define-map allowed-voting-tokens principal bool)

;; Proposal Data Structure
(define-map proposals
    uint 
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-utf8 1000),
        start-block-height: uint,
        end-block-height: uint,
        voting-token: principal,
        status: uint,
        yes-votes: uint,
        no-votes: uint,
        quorum-reached: bool,
        total-votes: uint,
        execution-delay: uint,
        executable-at: uint
    }
)

;; Vote Record
(define-map vote-records
    {proposal-id: uint, voter: principal}
    {amount: uint, vote: bool}
)

;; Helper functions for input validation
(define-private (is-valid-title (title (string-ascii 100)))
    (and 
        (not (is-eq title ""))
        (<= (len title) u100))
)

(define-private (is-valid-description (description (string-utf8 1000)))
    (and 
        (not (is-eq (len description) u0))
        (<= (len description) u1000))
)

(define-private (is-valid-execution-delay (delay uint))
    (<= delay (var-get max-execution-delay))
)

(define-private (is-valid-vote-amount (amount uint))
    (> amount u0)
)

;; Check if a token is whitelisted
(define-read-only (is-token-whitelisted (token principal))
    (default-to false (map-get? allowed-voting-tokens token))
)

;; Read Only Functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? vote-records {proposal-id: proposal-id, voter: voter})
)

(define-read-only (is-proposal-active (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (and 
            (is-eq (get status proposal) proposal-status-active)
            (<= (get start-block-height proposal) block-height)
            (> (get end-block-height proposal) block-height))
        false)
)

(define-read-only (can-execute (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (and
            (is-eq (get status proposal) proposal-status-succeeded)
            (>= block-height (get executable-at proposal)))
        false)
)

;; Admin function to manage allowed tokens
(define-public (set-allowed-token (token principal) (allowed bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set allowed-voting-tokens token allowed)
        (ok true)
    )
)

;; Public Functions
(define-public (create-proposal 
    (title (string-ascii 100))
    (description (string-utf8 1000))
    (voting-period uint)
    (voting-token <sip-010-trait>)
    (execution-delay uint))
    (let
        ((proposal-id (+ (var-get proposal-count) u1))
         (token-principal (contract-of voting-token)))
        
        ;; Input validation
        (asserts! (is-valid-title title) err-invalid-title)
        (asserts! (is-valid-description description) err-invalid-description)
        (asserts! (>= voting-period (var-get min-proposal-duration)) err-invalid-proposal)
        (asserts! (is-valid-execution-delay execution-delay) err-invalid-execution-delay)
        
        ;; Verify token is on the whitelist
        (asserts! (is-token-whitelisted token-principal) err-unauthorized-token)
        
        ;; Verify token contract implements the SIP-010 interface
        (try! (contract-call? voting-token get-name))
        
        ;; Create new proposal
        (map-set proposals proposal-id
            {
                creator: tx-sender,
                title: title,
                description: description,
                start-block-height: block-height,
                end-block-height: (+ block-height voting-period),
                voting-token: token-principal,
                status: proposal-status-active,
                yes-votes: u0,
                no-votes: u0,
                quorum-reached: false,
                total-votes: u0,
                execution-delay: execution-delay,
                executable-at: (+ block-height voting-period execution-delay)
            })
        
        ;; Increment proposal count
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote 
    (proposal-id uint)
    (vote-amount uint)
    (vote-for bool)
    (token <sip-010-trait>))
    (let
        ((proposal (unwrap! (get-proposal proposal-id) err-invalid-proposal))
         (token-principal (contract-of token)))
        
        ;; Input validation
        (asserts! (is-valid-vote-amount vote-amount) err-invalid-vote-amount)
        
        ;; Check if proposal is active
        (asserts! (is-proposal-active proposal-id) err-proposal-ended)
        
        ;; Check if voting token matches proposal's token
        (asserts! (is-eq token-principal (get voting-token proposal)) err-invalid-voting-token)
        
        ;; Check if voter has already voted
        (asserts! (is-none (get-vote proposal-id tx-sender)) err-already-voted)
        
        ;; Check if voter has enough balance
        (asserts! (>= (try! (contract-call? token get-balance tx-sender)) vote-amount) 
                 err-insufficient-voting-power)
        
        ;; Record vote
        (map-set vote-records 
            {proposal-id: proposal-id, voter: tx-sender}
            {amount: vote-amount, vote: vote-for})
        
        ;; Update proposal vote counts
        (map-set proposals proposal-id
            (merge proposal 
                {
                    yes-votes: (if vote-for (+ (get yes-votes proposal) vote-amount) (get yes-votes proposal)),
                    no-votes: (if vote-for (get no-votes proposal) (+ (get no-votes proposal) vote-amount)),
                    total-votes: (+ (get total-votes proposal) vote-amount),
                    quorum-reached: (>= (+ (get total-votes proposal) vote-amount) (var-get quorum-threshold))
                }))
        
        (ok true)
    )
)

(define-public (finish-proposal (proposal-id uint))
    (let ((proposal (unwrap! (get-proposal proposal-id) err-invalid-proposal)))
        
        ;; Check if proposal has ended
        (asserts! (>= block-height (get end-block-height proposal)) err-proposal-active)
        ;; Check if proposal is still active (hasn't been finished yet)
        (asserts! (is-eq (get status proposal) proposal-status-active) err-proposal-ended)
        
        ;; Calculate if proposal passed
        (let ((passed (and 
                (get quorum-reached proposal)
                (>= (get yes-votes proposal) (var-get vote-threshold)))))
            
            ;; Update proposal status
            (map-set proposals proposal-id
                (merge proposal 
                    {status: (if passed proposal-status-succeeded proposal-status-failed)}))
            
            (ok passed))
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (get-proposal proposal-id) err-invalid-proposal)))
        
        ;; Check if proposal can be executed
        (asserts! (can-execute proposal-id) err-not-executable)
        
        ;; Update proposal status
        (map-set proposals proposal-id
            (merge proposal {status: proposal-status-executed}))
        
        (ok true)
    )
)

;; Admin Functions
(define-public (update-quorum-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-threshold u0) err-invalid-quorum)
        (var-set quorum-threshold new-threshold)
        (ok true)
    )
)

(define-public (update-vote-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-threshold u0) err-invalid-quorum)
        (var-set vote-threshold new-threshold)
        (ok true)
    )
)

(define-public (update-min-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= new-duration u14400) err-invalid-proposal)
        (var-set min-proposal-duration new-duration)
        (ok true)
    )
)
