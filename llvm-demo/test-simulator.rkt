#lang s-exp rosette

(require "llvm-demo-parser.rkt" "llvm-demo-printer.rkt" "llvm-demo-machine.rkt"
         "llvm-demo-simulator-rosette.rkt"
         "llvm-demo-simulator-racket.rkt"
         "llvm-demo-validator.rkt")

;; Step -1: familiar yourself with default inst

;; Step 0: set up bitwidth for Rosette
(current-bitwidth 32)

;; Step 1: Test parser and printer
(pretty-display "Step 1: test parser and printer.")
(define parser (new llvm-demo-parser%))
(define machine (new llvm-demo-machine% [config 4]))
(define printer (new llvm-demo-printer% [machine machine]))

(define code
(send parser ast-from-string "
  %1 = add i32 -1, %x0
"))

(send printer print-struct code)
(send printer print-syntax code)

(define encoded-code (send printer encode code))
(send printer print-struct encoded-code)
(newline)

;; Step 2: Test concrete simulator
(pretty-display "Step 2: interpret program using simulator writing in Rosette.")
(define input-state (vector 1 22 3 4))
(define simulator-rosette (new llvm-demo-simulator-rosette% [machine machine]))
(send simulator-rosette interpret encoded-code input-state)
(newline)

;; Step 3: Unknown program
(pretty-display "Step 3: test parser and printer for unknown program.")
(define code?
(send parser ast-from-string "
? ?
"))
;; Use validator to encode unknown program instead of printer
(define validator (new llvm-demo-validator%
                       [machine machine] [printer printer]
                       [simulator simulator-rosette]))
(define encoded-code? (send validator encode-sym code?))

(send printer print-struct code?)
(send printer print-struct encoded-code?)
(newline)

;; Step 4: interpret unknown program
(pretty-display "Step 4: interpret unknown program.")
(send simulator-rosette interpret encoded-code? input-state)
(newline)

;; Step 5: interpret concrete program with symbolic inputs
(pretty-display "Step 5: interpret concrete program with symbolic inputs.")
(define (sym-input)
  (define-symbolic* in number?)
  in)

(define input-state-sym (send machine get-state sym-input))
(send simulator-rosette interpret encoded-code input-state-sym)
(newline)

;; Step 6: duplicate rosette simulator to racket simulator
(pretty-display "Step 6: interpret program using simulator writing in Racket.")
(define simulator-racket (new llvm-demo-simulator-racket% [machine machine]))
(send simulator-racket interpret encoded-code input-state)