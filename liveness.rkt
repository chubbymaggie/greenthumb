#lang racket

(require "ast.rkt" "f18a.rkt" "f18a-liveness.rkt" "state.rkt")
(provide relax-constraint)

;; TODO: check-memory with detail when synthesis
(define debug #t)

(define (relax-constraint code prog func-dict [bit 18])
  
  (define (analyze x cnstr)
      
    (define (live b cnstr)
      (set-constraint! b cnstr)
      (when debug
	    (pretty-display "====================== work on ========================")
	    (print-struct b))
      (define start-state (default-state (generate-info prog (list b)) (sym-input)))
      (define end-state (interpret bit (encode (block-body b)) start-state))
      (define ret (extract-liveness start-state end-state (generate-constraint b)))
      (when debug
	    (pretty-display "return:")
	    (pretty-display ret))
      ret)
    
    (cond
     [(list? x) 
      ;;(pretty-display `(analyze list ,cnstr))
      (foldr analyze cnstr x)]
     
     [(block? x) 
      ;;(pretty-display `(analyze block ,cnstr))
      (live x cnstr)]
     
     [(forloop? x)
      ;;(pretty-display `(analyze forloop))
      (define (inner body cnstr-old)
	(define cnstr-new (analyze body cnstr-old))
	;;(pretty-display `(analyze forloop inner ,cnstr-old ,cnstr-new ,(contain cnstr-old cnstr-new)))
	(if (contain cnstr-old cnstr-new)
	    (analyze (forloop-init x) cnstr-old)
	    (inner body (union cnstr-new cnstr-old))))
      (inner (forloop-body x) cnstr)]
     
     [(ift? x) (analyze (ift-t x) cnstr)]
     
     [(-ift? x) (analyze (-ift-t x) cnstr)]
     
     [(iftf? x)
      (define t (analyze (iftf-t x) cnstr))
      (define f (analyze (iftf-f x) cnstr))
      (union t f)]
     
     [(-iftf? x)
      (define t (analyze (-iftf-t x) cnstr))
      (define f (analyze (-iftf-f x) cnstr))
      (union t f)]

     [(assumption? x)
      cnstr]
     
     [(call? x)
      ;;(pretty-display `(analyze call ,cnstr))
      (if (inline? x)
	  (let* ([name (call-name x)]
		 [val (hash-ref func-dict name)])
	    ;; (if (label? val)
	    ;; 	(begin
	    ;; 	  (pretty-display (format "RELAX: ~a" name))
	    ;; 	  (let ([new-cnstr (analyze (label-body val) cnstr)])
	    ;; 	    (hash-set! func-dict name new-cnstr)
	    ;; 	    new-cnstr))
	    ;; 	val))
	    (analyze (label-body val) cnstr)) ;; need union
	  cnstr)
      ]
     
     [else (raise (format "relax-constraint: analyze: unimplemented for ~a" x))]
     ))
  
  (when debug
	(pretty-display "RELAX CONSTRAINT")
	(print-struct code))
  (define b (last-block code))
  ;; If b is #f, no need to perform liveness analysis.
  (when b (analyze code (generate-constraint b))))