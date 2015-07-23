#lang racket

(require "../ops-racket.rkt" "../ast.rkt"
         "GA-machine.rkt" "GA-simulator-racket.rkt"
         "GA-printer.rkt" "GA-parser.rkt")

(provide GA-inverse%)
 
(define-syntax-rule (modulo- x y) (if (< x 0) (+ x y) x))
(define-syntax-rule (modulo+ x y) (if (>= x 8) (- x y) x))

(define GA-inverse%
  (class object%
    (super-new)
    (init-field machine simulator)
    (public gen-inverse-behavior interpret-inst)
    
    (define bit (get-field bit machine))
    (define inst-id (get-field inst-id machine))
    (define val-range
      (and (<= bit 4)
	   (for/list ([v (arithmetic-shift 1 bit)]) (finitize v bit))))
    (define nmems (send machine get-nmems))
    
    (define behaviors-bw (make-hash))
    
    (define UP (get-field UP machine))
    (define DOWN (get-field DOWN machine))
    (define LEFT (get-field LEFT machine))
    (define RIGHT (get-field RIGHT machine))
    (define IO (get-field IO machine))

    ;; Generate inverse function for the following instructions:
    ;;   +* 2* 2/ - + and or drop
    (define (gen-inverse-behavior my-inst)
      (define opcode-id (inst-op my-inst))
      (define opcode-name (vector-ref inst-id opcode-id))

      (define behavior-bw (make-hash))
      (cond
       [(member opcode-name '(2* 2/ -))
        (for ([v val-range])
             (let* ([state (default-state machine 0 (thunk 0) [t v])]
                    [out-state 
                     (with-handlers*
                      ([exn? (lambda (e) #f)])
                      (send simulator interpret (vector my-inst) state #:dep #f))]
                    [out-v (and out-state (progstate-t out-state))])
               (when out-v
                     (if (hash-has-key? behavior-bw out-v)
                         (hash-set! behavior-bw out-v (cons v (hash-ref behavior-bw out-v)))
                         (hash-set! behavior-bw out-v (list v))))))]


       [(member opcode-name '(+ and or))
        (for* ([v1 val-range]
               [v2 val-range])
              (let* ([state (default-state machine 0 (thunk 0) [t v1] [s v2])]
                     [out-state 
                      (with-handlers*
                       ([exn? (lambda (e) #f)])
                       (send simulator interpret (vector my-inst) state #:dep #f))]
                     [out-v (and out-state (progstate-t out-state))])
               (when out-v
                     (if (hash-has-key? behavior-bw out-v)
                         (hash-set! behavior-bw out-v
                                    (cons (list v1 v2) (hash-ref behavior-bw out-v)))
                         (hash-set! behavior-bw out-v
                                    (list (list v1 v2)))))))]

       [(member opcode-name '(+*))
        (for* ([v1 val-range]
               [v2 val-range]
               [a val-range])
              (let* ([state (default-state machine 0 (thunk 0) [t v1] [s v2] [a a])]
                     [out-state 
                      (with-handlers*
                       ([exn? (lambda (e) #f)])
                       (send simulator interpret (vector my-inst) state #:dep #f))]
                     [key (and out-state
                               (list (progstate-t out-state)
                                     (progstate-s out-state)
                                     (progstate-a out-state)))])
                (when key
                      (for ([key (get-all-keys key)])
                           (if (hash-has-key? behavior-bw key)
                               (hash-set! behavior-bw key
                                          (cons (list v1 v2 a) (hash-ref behavior-bw key)))
                               (hash-set! behavior-bw key
                                          (list (list v1 v2 a))))))))])

      (hash-set! behaviors-bw opcode-id behavior-bw))

    (define-syntax-rule (stack->vector x) (send machine stack->vector x))

    (define (get-all-keys key)
      (drop ;; drop (list #f #f #f)
       (for*/list ([a 2]
                   [b 2]
                   [c 2])
         (list (and (= a 1) (first key))
               (and (= b 1) (second key))
               (and (= c 1) (third key))))
       1))
               
    (define (interpret-inst my-inst state-vec old-liveout)
      (define state (send machine vector->progstate state-vec))
      (define a (progstate-a state))
      (define b (progstate-b state))
      (define r (progstate-r state))
      (define s (progstate-s state))
      (define t (progstate-t state))
      (define data (progstate-data state))
      (define data-sp (stack-sp (progstate-data state)))
      (define data-body (vector-copy (stack-body (progstate-data state))))
      (define return-sp (stack-sp (progstate-return state)))
      (define return-body (vector-copy (stack-body (progstate-return state))))
      (define memory (vector-copy (progstate-memory state)))
      (define recv (progstate-recv state))
      (define comm (progstate-comm state))
      
      (define nmems (vector-length memory))
      
      (define opcode-id (inst-op my-inst))
      (define opcode-name (vector-ref inst-id opcode-id))
      (define const (inst-args my-inst))
      
      (define out-list (list))

      (define (snapshot)
        (set! out-list
              (cons
               (vector a b r s t 
                       (stack->vector (stack data-sp data-body))
                       (stack->vector (stack return-sp return-body))
                       memory recv comm)
               out-list)))
      
      ;; Pushes a value to the given stack's body.
      (define-syntax-rule (push-stack! x-sp x-body value)
	(begin
	  (set! x-sp (modulo+ (add1 x-sp) 8))
	  (vector-set! x-body x-sp value)
	  ))

      ;; Pops from the given stack's body.
      (define-syntax-rule (pop-stack! x-sp x-body)
	(let ([ret-val (vector-ref x-body x-sp)])
          (vector-set! x-body x-sp #f)
	  (set! x-sp (modulo- (sub1 x-sp) 8))
	  ret-val))

      ;; Pushes to the data stack.
      (define (push! value)
	(push-stack! data-sp data-body s)
	(set! s t)
	(set! t value))
      
      ;; Pushes to the return stack.
      (define (r-push! value)
	(push-stack! return-sp return-body r)
	(set! r value))
      
            ;; Pops from the data stack.
      (define (pop!)
        (set! t s)
        (set! s (pop-stack! data-sp data-body))
        )
      
      ;; Pops from the return stack.
      (define (r-pop!)
        (set! r (pop-stack! return-sp return-body))
        )
      
      (define-syntax-rule (eq-pop! value)
        (when (and t (or (not value) (= t value)))
              (when (not value) (set! value t))
              (set! t s)
              (set! s (pop-stack! data-sp data-body))
              (snapshot)))
      
      ;; Mutate comm and rev
      (define (memeq? addr val)
	(define (read port)
          (define ret
            (and (not (empty? comm))
                 (equal? (list val port 0) (car comm))))
          (when ret 
            (set! recv (cons val recv))
            (set! comm (cdr comm)))
          ret)
            
	(cond
	 [(equal? addr UP)    (read UP)]
	 [(equal? addr DOWN)  (read DOWN)]
	 [(equal? addr LEFT)  (read LEFT)]
	 [(equal? addr RIGHT) (read RIGHT)]
	 [(equal? addr IO)    (read IO)]
         [(and (>= addr 0) (< addr nmems))
          (let ([tmp (vector-ref memory addr)])
            (unless tmp (vector-set! memory addr val) (set! tmp val))
            (= tmp val))]        
	 [else #f]))

      (define (read-memory-rm addr)
	(define (read port)
          (define ret
            (and (not (empty? comm))
                 (let ([tuple (car comm)])
                   (and (equal? (second tuple) port)
                        (equal? (third tuple) 1)
                        (first tuple)))))
          (when ret (set! comm (cdr comm)))
          ret)
        
	(cond
	 [(equal? addr UP)    (read UP)]
	 [(equal? addr DOWN)  (read DOWN)]
	 [(equal? addr LEFT)  (read LEFT)]
	 [(equal? addr RIGHT) (read RIGHT)]
	 [(equal? addr IO)    (read IO)]
	 [(and (>= addr 0) (< addr nmems))
          (let ([tmp (vector-ref memory addr)])
            (vector-set! memory addr #f)
            tmp)]
         [else #f]))

      (define-syntax-rule (memeq-pop! a f)
        (when t
              (if a
                  (begin
                    (set! a (f a))
                    (when (memeq? a t) (pop!) (snapshot)))
                  (let ([t-org t]
                        [mem-copy (vector-copy memory)])
                    (pop!)
                    (for ([v (append (range nmems) (list UP DOWN LEFT RIGHT IO))])
                         (set! memory (vector-copy mem-copy))
                         (set! a v)
                         (when (memeq? a t-org) (snapshot)))))))

      (define-syntax-rule (mem-to-stack-rm a f)
        (if a
            (begin
              (set! a (f a))
              (let ([val (read-memory-rm a)])
                (when val (push! val) (snapshot))))
            (let ([mem-copy (vector-copy memory)])
              (push! #f)
              (for ([v (append (range nmems) (list UP DOWN LEFT RIGHT IO))])
                   (set! memory (vector-copy mem-copy))
                   (set! a v)
                   (let ([val (read-memory-rm a)])
                     (when val (set! t val) (snapshot)))))))

      (define (t-t)
        (define behavior (hash-ref behaviors-bw opcode-id))
        (when (hash-has-key? behavior t)
              (define in-t-list (hash-ref behavior t))
              (define in-data (stack->vector (stack data-sp data-body)))
              (define in-return (stack->vector (stack return-sp return-body)))
              (set! out-list
                    (for/list ([in-t in-t-list])
                              (vector a b r s in-t
                                      in-data
                                      in-return
                                      memory recv comm)))))

      (define (ts-t)
        (define behavior (hash-ref behaviors-bw opcode-id))
        (when (hash-has-key? behavior t)
              (define in-list (hash-ref behavior t))
          ;; (pretty-display `(in-list ,in-list))
          (push! #f)
          (define in-data (stack->vector (stack data-sp data-body)))
          (define in-return (stack->vector (stack return-sp return-body)))
          (set! out-list
                (for/list ([in in-list])
                          (let ([in-t (first in)]
                                [in-s (second in)])
                            (vector a b r in-s in-t
                                    in-data
                                    in-return
                                    memory recv comm))))))

      (define (tsa-tsa)
        (define behavior (hash-ref behaviors-bw opcode-id))
        (define key (list t s a))
        (when (hash-has-key? behavior key)
              (define in-list (hash-ref behavior key))
              (define in-data (stack->vector (stack data-sp data-body)))
              (define in-return (stack->vector (stack return-sp return-body)))
              (set! out-list
                    (for/list ([in in-list])
                              (let ([in-t (first in)]
                                    [in-s (second in)]
                                    [in-a (third in)])
                                (vector in-a b r in-s in-t
                                        in-data
                                        in-return
                                        memory recv comm))))))

      
      (define-syntax-rule (inst-eq x) (equal? x opcode-name))

      (cond
       [(inst-eq `@p)   (eq-pop! const)]
       [(inst-eq `@+)   (memeq-pop! a sub1)]
       [(inst-eq `@b)   (memeq-pop! b identity)]
       [(inst-eq `@)    (memeq-pop! a identity)]
       
       [(inst-eq `!+)   (mem-to-stack-rm a sub1)]
       [(inst-eq `!b)   (mem-to-stack-rm b identity)]
       [(inst-eq `!)    (mem-to-stack-rm a identity)]
       
       [(inst-eq `+*)   (when (or t s a) (tsa-tsa))]
       [(member opcode-name '(2* 2/ -)) (when t (t-t))]
       [(member opcode-name '(+ and or)) (when t (ts-t))]
        
       [(inst-eq `drop) 
        (push! #f) (snapshot) ;(drop!)
        ]
       [(inst-eq `dup)  (eq-pop! s)]
       [(inst-eq `pop)  (when t (r-push! t) (pop!) (snapshot))]
       [(inst-eq `a)    (eq-pop! a)]
       [(inst-eq `nop)  (snapshot)]
       [(inst-eq `push) (when r (push! r) (r-pop!) (snapshot))]
       [(inst-eq `b!)   (when b (push! b) (set! b #f) (snapshot))]
       [(inst-eq `a!)   (when a (push! a) (set! a #f) (snapshot))]
       [(inst-eq `over)
        (let ([val (get-stack data 0)]
              [t-org t])
          (when (and t (or (not val) (= t val)))
            (set! t s)
            (pop-stack! data-sp data-body)
            (set! s t-org)
            (snapshot)))]
       [else (assert #f (format "invalid instruction ~a" inst))])

      out-list)

    ))

#|
(define machine (new GA-machine% [bit 4]))
(send machine set-config 0)
(define simulator (new GA-simulator-racket% [machine machine]))

(define inverse (new GA-inverse% [machine machine] [simulator simulator]))
(define printer (new GA-printer% [machine machine]))
(define parser (new GA-parser%))
(define my-inst-0
  (vector-ref (send printer encode 
                    (send parser ast-from-string "+*"))
              0))

(define my-inst 
  (vector-ref (send printer encode 
                    (send parser ast-from-string "!"))
              0))

(define input-state (vector #f 10 #f 2 99
                            (vector #f #f #f #f #f #f #f #f)
                            (make-vector 8 #f)
                            (vector 1 2) (list) 
                            (list (list 3 (get-field DOWN machine) 1))))
                            

(send inverse gen-inverse-behavior my-inst-0)
(send inverse interpret-inst my-inst input-state #f)
|#
