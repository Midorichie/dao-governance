;; governance-token.clar
;; A SIP-010 compliant governance token implementation

;; Import SIP-010 trait from local contract
(use-trait ft-trait .sip-010-trait.sip-010-trait)

;; Implement trait
(impl-trait .sip-010-trait.sip-010-trait)

(define-fungible-token dao-token)

;; Constants and Errors
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-zero-amount (err u102))
(define-constant err-transfer-self (err u103))
(define-constant err-insufficient-balance (err u104))

;; SIP-010 Standard Functions
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        ;; Input validation
        (asserts! (> amount u0) err-zero-amount)
        (asserts! (not (is-eq sender recipient)) err-transfer-self)
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (asserts! (<= amount (ft-get-balance dao-token sender)) err-insufficient-balance)
        
        ;; Perform transfer
        (try! (ft-transfer? dao-token amount sender recipient))
        
        ;; Handle memo if present
        (match memo memo-data 
            (begin 
                (print memo-data) 
                (ok true))
            (ok true))
    )
)

(define-read-only (get-name)
    (ok "DAO Governance Token")
)

(define-read-only (get-symbol)
    (ok "DAO")
)

(define-read-only (get-decimals)
    (ok u6)
)

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance dao-token who))
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply dao-token))
)

(define-read-only (get-token-uri)
    (ok (some u"https://dao.governance/token-metadata.json"))
)

;; Governance Specific Functions
(define-read-only (get-voting-power (account principal))
    (ok (ft-get-balance dao-token account))
)

;; Initialize contract
(begin
    (try! (ft-mint? dao-token u1000000000000 contract-owner))
)
