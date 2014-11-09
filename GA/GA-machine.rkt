#lang racket

(require "../machine.rkt" "../ops-racket.rkt")

(provide GA-machine% (all-defined-out))

(struct syninfo   (memsize recv indexmap))
(struct blockinfo (cnstr recv))
(struct labelinfo (data return simple))

(struct progstate (a b r s t data return memory recv comm) 
        #:mutable #:transparent)

(struct progstate+ progstate (extra))

(define UP #x145) ;325
(define DOWN #x115) ;277
(define LEFT #x175) ;373
(define RIGHT #x1d5) ;469
(define IO #x15d)


;;;;;;;;;;;;;; STACK ;;;;;;;;;;;;;;;;;;
(struct stack (sp body))

;;; Print a circular stack:
(define (display-stack x)
  (define-syntax-rule (modulo- x y) (if (< x 0) (+ x y) x))
  ;; (pretty-display (format " ~a" stack)))
  (if (stack? x)
      (for [(i (in-range 0 8))]
           (display (format " ~a" (vector-ref (stack-body x)
                                              (modulo- (- (stack-sp x) i) 8)))))
      (display (format " ~a" x))))

;;;;;;;;;;;;;; END STACK ;;;;;;;;;;;;;;;;

(define-syntax-rule (build-vector n init)
  (let ([vec (make-vector n)])
    (for ([i (in-range n)])
	 (vector-set! vec i (init)))
    vec))

(define-syntax default-state
  (syntax-rules ()
    ((default-state machine recv-n init)
     (progstate (init) (init) (init) (init) (init)
		(stack 0 (build-vector 8 init))
		(stack 0 (build-vector 8 init))
		(build-vector (send machine get-nmems) init)
		(for/list ([i recv-n]) (init))
		(list)))

    ((default-state machine recv-n init [data-pair (i i-val) ...] [key val] ...)
     (let* ([state (default-state machine recv-n init)]
            [body (stack-body (progstate-data state))]
            [pairs (list (cons i i-val) ...)])
       (for ([p pairs])
            (vector-set! body (modulo (- (car p)) 8) (cdr p)))
       (struct-copy progstate state [data (stack 0 body)] [key val] ...)))

    ((default-state machine recv-n init [key val] ...)
     (struct-copy progstate (default-state machine recv-n init) [key val] ...))
    
    ((default-state machine)
     (default-state machine 0 (lambda () 0)))
    ))

;;; The empty constraint. Pretty useless.
(define constraint-none (progstate #f #f #f #f #f #f #f #f #f #t))

;;; Constrain everything. We must have perfection!
(define constraint-all (progstate #t #t #t #t #t 8 8 #t #f #t))

;;; Defines a constraint for some fields. For example, `(constraint
;;; t)' is the same as constraint-only-t and evaluates to `(progstate
;;; #f #f #f #f #f #f #t #f #f #f)'. If you want to constrain
;;; everything *except* the given fields, start with the except
;;; keyword: `(constrain except t)' constrains everything but t. 
(define-syntax constraint
  (syntax-rules (except data return none)

    ((constraint (return val1) (data val2) var ...)  
     (struct-copy progstate constraint-none [return val1] [data val2] [var #t] ...))
    ((constraint (data val2) (return val1) var ...)  
     (struct-copy progstate constraint-none [return val1] [data val2] [var #t] ...))

    ((constraint (return val1) (data val2))
     (struct-copy progstate constraint-none [return val1] [data val2]))
    ((constraint (data val2) (return val1))
     (struct-copy progstate constraint-none [return val1] [data val2]))

    ((constraint (data val) var ...)  
     (struct-copy progstate constraint-none [data val] [var #t] ...))
    ((constraint (data val))  
     (struct-copy progstate constraint-none [data val]))
    ((constraint (return val) var ...)  
     (struct-copy progstate constraint-none [return val] [var #t] ...))
    ((constraint (return val))  
     (struct-copy progstate constraint-none [return val]))

    ((constraint except var ...) (struct-copy progstate constraint-all  [var #f] ...))
    ((constraint var ...)        (struct-copy progstate constraint-none [var #t] ...))
    ))

(define (constrain-stack machine precond [state (default-state machine)])
  (when (list? precond)
    (for ([assume precond]
          [i (reverse (range (length precond)))])
      (cond
       [(and assume (= i 0)) (set-progstate-t! state assume)]
       [(and assume (= i 1)) (set-progstate-s! state assume)]
       [(and assume (< i 10))
        (let ([body (stack-body (progstate-data state))])
          (vector-set! body (modulo (- 2 i) 8) assume))]

       [(and assume (<= i 10))
	(raise "A small function cannot have more than 10 parameters.")]
       )))
  state)

(define GA-machine%
  (class machine%
    (super-new)
    (inherit-field bit nop-id random-input-bit inst-id classes classes-len perline)
    (inherit print-line)
    (override set-config get-config set-config-string
              adjust-config finalize-config config-exceed-limit?
              get-state display-state 
              output-constraint-string output-assume-string
	      no-assumption
              display-state-text parse-state-text
              progstate->vector vector->progstate
	      window-size)

    (set! bit 18)
    (set! random-input-bit 16)
    (set! nop-id 0)
    (set! inst-id '#(nop @p @+ @b @ !+ !b ! +* 2* 
			 2/ - + and or drop dup pop over a 
			 push b! a!))

    ;; Instruction classes
    (set! classes 
          (vector '(@+ @b @) 
		  '(!+ !b !)
		  '(+* 2* 2/ -)
		  '(+ and or drop push b! a!) 
		  '(dup pop over a)))

    (set! classes-len (vector-length classes))
    (set! perline 8)

    (define nmems 1)
    (define/public (get-nmems) nmems)

    (define (window-size) 100)
    (define (get-config) nmems)
    (define (set-config info) (set! nmems info))
    (define (set-config-string info) info)
    (define (adjust-config info) (* 2 info))
    (define (finalize-config info) (add1 info))
    (define (config-exceed-limit? info) (> info 100))
    (define (output-assume-string machine-var x)
      (if x
          (format "(constrain-stack ~a '~a)" machine-var x)
          #f))
    (define (output-constraint-string machine-var live-out)
      ;; live-out is something like '((data . 0) (return . 1) memory a)
      (if live-out
          (format "(send ~a output-constraint '~a)" machine-var live-out)
          #f))

    (define/public (output-constraint lst [extra-data 0] [extra-return 0])
      (define a #f) 
      (define b #f) 
      (define memory (make-vector nmems #f))
      (define data extra-data)
      (define return extra-return)
      (for ([i lst])
	   (cond
	    [(equal? i 'a)      (set! a #t)]
	    [(equal? i 'b)      (set! b #t)]
	    [(equal? i 'memory) (set! memory (make-vector nmems #t))]
	    [(and (pair? i) (equal? (car i) 'data))   (set! data (+ data (cdr i)))]
	    [(and (pair? i) (equal? (car i) 'return)) (set! return (+ return (cdr i)))]
	    [else (raise (format "create-constraint: unimplemented for ~a" i))]))
      (struct-copy progstate constraint-none [a a] [b b] [memory memory]
		   [t (>= data 1)] [s (>= data 2)] [data (and (> (- data 2) 0) (- data 2))]
		   [r (>= return 1)] [return (and (> (- return 1) 0) (- return 1))]))

    (define (get-state init recv-n) ;; TODO: track all get-state
      (default-state this recv-n init))
      
    (define (display-state state)
      (pretty-display (format "a:~a b:~a"
			      (progstate-a state) (progstate-b state)))
      (display-data state)
      (display-return state)
      (display-memory state)
      (display-comm state)
      )

    ;; Print the data stack:
    (define (display-data state)
      (display (format "|d> ~a ~a" (progstate-t state) (progstate-s state)))
      (display-stack (progstate-data state))
      (newline))

    ;; Print the return stack:
    (define (display-return state)
      (display (format "|r> ~a" (progstate-r state)))
      (display-stack (progstate-return state))
      (newline))

    ;; Print the memory:
    (define (display-memory state)
      (define memory (progstate-memory state))
      (display "mem: ")
      (for ([i (in-range 0 (vector-length memory))])
	   (display (format "~a " (vector-ref memory i))))
      (newline))

    ;; Print comm info.
    (define (display-comm state)
      (display "recv: ")
      (pretty-display (progstate-recv state))
      (display "comm: ")
      (pretty-display (progstate-comm state)))
    
    (define (get-stack stack i)
      (define-syntax-rule (modulo- x y) (if (< x 0) (+ x y) x))
      (vector-ref (stack-body stack) (modulo- (- (stack-sp stack) i) 8)))

    (define (stack->vector x)
      (if (stack? x)
          (for/vector ([i 8]) (get-stack x i))
          x))
    
    (define (vector->stack x)
      (if (vector? x)
          (stack 7 (list->vector (reverse (vector->list x))))
          x))
    
    (define (progstate->vector x)
      (vector (progstate-a x)
              (progstate-b x)
              (progstate-r x)
              (progstate-s x)
              (progstate-t x)
              (stack->vector (progstate-data x))
              (stack->vector (progstate-return x))
              (progstate-memory x)
              (progstate-recv x)
              (progstate-comm x)))

    (define (vector->progstate x)
      (progstate (vector-ref x 0)
                 (vector-ref x 1)
                 (vector-ref x 2)
                 (vector-ref x 3)
                 (vector-ref x 4)
                 (vector->stack (vector-ref x 5))
                 (vector->stack (vector-ref x 6))
                 (vector-ref x 7)
                 (vector-ref x 8)
                 (vector-ref x 9)))

    (define (display-state-text pair)
      (display (format "~a," (car pair)))
      (define state (cdr pair))
      (define a (progstate-a state))
      (define b (progstate-b state))
      (define r (progstate-r state))
      (define s (progstate-s state))
      (define t (progstate-t state))
      (define data (progstate-data state))
      (define return (progstate-return state))
      (define memory (progstate-memory state))
      (define recv (progstate-recv state))
      (define comm (progstate-comm state))

      (display (format "~a,~a,~a,~a,~a," a b r s t))
      ;; data
      (display (format "~a;" (stack-sp data)))
      (display (string-join (map number->string (vector->list (stack-body data)))))
      (display ",")
      ;; return
      (display (format "~a;" (stack-sp return)))
      (display (string-join (map number->string (vector->list (stack-body return)))))
      (display ",")
      ;; memory
      (display "")
      (display (string-join (map number->string (vector->list memory))))
      (display ",")
      ;; recv
      (display (string-join (map number->string recv)))
      (display ",")
      ;; comm
      (display (string-join 
                (map (lambda (x) 
                       (format "~a ~a ~a" (first x) (second x) (third x)))
                     comm)
                ";"))
      (pretty-display ","))

    (define (parse-state-text str)
      (define tokens (list->vector (string-split str ",")))
      (define-syntax-rule (to-number index) (string->number (vector-ref tokens index)))
      (define a (to-number 1))
      (define b (to-number 2))
      (define r (to-number 3))
      (define s (to-number 4))
      (define t (to-number 5))
      (define raw-data (string-split (vector-ref tokens 6) ";"))
      (define data (stack (string->number (first raw-data))
                          (list->vector 
                           (map string->number (string-split (second raw-data))))))
      (define raw-return (string-split (vector-ref tokens 7) ";"))
      (define return (stack (string->number (first raw-return))
                            (list->vector 
                             (map string->number (string-split (second raw-return))))))
      (define memory (list->vector (map string->number (string-split (vector-ref tokens 8)))))
      (define recv (map string->number (string-split (vector-ref tokens 9))))
      (define raw-comm (string-split (vector-ref tokens 10) ";"))
      (define comm (map (lambda (x) (map string->number (string-split x))) raw-comm))
      (cons (equal? (vector-ref tokens 0) "#t")
            (progstate a b r s t data return memory recv comm)))

    (define (no-assumption)
      (default-state this))
    ))
