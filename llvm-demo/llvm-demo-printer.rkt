#lang racket

(require "../printer.rkt" 
         "../ast.rkt")

(provide llvm-demo-printer%)

(define llvm-demo-printer%
  (class printer%
    (super-new)
    (inherit-field machine)
    (override encode-inst decode-inst print-syntax-inst) ;; print-struct-inst

    (define (print-syntax-inst x [indent ""])
      (define op (inst-op x))
      (unless (equal? op "nop")
              (define args (inst-args x))
              (display (format "~a = ~a i32 ~a" 
                               (vector-ref args 0)
                               op
                               (vector-ref args 1)))
              (for ([i (range 2 (vector-length args))])
                   (display (format ", ~a" (vector-ref args i))))
              (newline)))

    (define name2num (make-hash))
    (define num2name (make-vector 100))
    (define n 0)

    (define-syntax-rule (char1=% x) (equal? (substring x 0 1) "%"))
				  
    ;; Convert from string to number representation.
    (define (encode-inst x)
      (cond
       [(equal? (inst-op x) "nop") (inst (get-field nop-id machine) (vector))]
       [else
        (define args (inst-args x))
        (define last-in (vector-ref args (sub1 (vector-length args))))
        (define first-in (vector-ref args 1))
        (define new-args
          (for/vector ([arg args])
                      (if (equal? (substring arg 0 1) "%")
                          (if (hash-has-key? name2num arg)
                              (hash-ref name2num arg)
                              (let ([id n])
                                (set! n (add1 n))
                                (hash-set! name2num arg id)
                                (vector-set! num2name id arg)
                                id))
                          (string->number arg))))
        (define op
          (string->symbol
           (cond
            [(and (char1=% first-in) (char1=% last-in))
             (inst-op x)]
            [(char1=% first-in)
             (string-append (inst-op x) "#")]
            [(char1=% last-in)
             (string-append "_" (inst-op x))]
            [else
             (raise "Not support %out = op <imm>, <imm>")])))
        (inst (send machine get-inst-id op) new-args)]))
    
    
    (define (decode-inst x)
      (define op (symbol->string (send machine get-inst-name (inst-op x))))
      (cond
       [(equal? op "nop") (inst op (vector))]
       [else
        (define args (inst-args x))
        (define first-in (vector-ref args 1))
        (define last-in (vector-ref args (sub1 (vector-length args))))
        (cond
         [(regexp-match #rx"#" op)
          (set! op (substring op 0 (sub1 (string-length op))))
          (set! first-in (vector-ref num2name first-in))
          ]
         [(regexp-match #rx"_" op)
          (pretty-display `(arg ,first-in ,last-in))
          (set! op (substring op 1))
          (set! last-in (vector-ref num2name last-in))
          ]
         [else
          (set! first-in (vector-ref num2name first-in))
          (set! last-in (vector-ref num2name last-in))])
        
        (define out (vector-ref num2name (vector-ref args 0)))

        (if (= (vector-length args) 3)
            (inst op (vector out first-in last-in))
            (inst op (vector out first-in)))]))

    
    (define/public (encode-live x)
      (define live (make-vector (send machine get-config) #f))
      (for ([v x])
           (vector-set! live (hash-ref name2num (symbol->string v)) #t))
      live)

    ))