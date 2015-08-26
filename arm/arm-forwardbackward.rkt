#lang racket

(require "../forwardbackward.rkt" "../ast.rkt" "../ops-racket.rkt"
         "arm-ast.rkt" "arm-machine.rkt"
         "arm-simulator-racket.rkt" "arm-validator.rkt"
         "arm-enumerative.rkt" "arm-inverse.rkt")

(provide arm-forwardbackward%)

(define arm-forwardbackward%
  (class forwardbackward%
    (super-new)
    (inherit-field machine printer simulator validator
                   enum inverse simulator-abst validator-abst)
    (override len-limit window-size
              mask-in inst->vector
              reduce-precision increase-precision
	      get-live-mask try-cmp? combine-live sort-live sort-live-bw)

    ;; Num of instructions that can be synthesized within a minute.
    (define (len-limit) 2)

    ;; Context-aware window decomposition size L.
    ;; The cooperative search tries L/2, L, 2L, 4L.
    (define (window-size) 4)
    
    ;; Initialization
    (set! simulator (new arm-simulator-racket% [machine machine]))
    (set! validator (new arm-validator% [machine machine] [printer printer]))

    ;; Actual bitwidth
    (define bit-precise (get-field bit machine))
    ;; Reduce bitwidth
    (define bit 4)
    (define nregs #f)
    (define stack 4)
    
    ;; Initlized required fields.
    (let* ([machine-abst (new arm-machine% [bit bit])]
           [config (send machine get-config)])
      (set! nregs (first config))
      (send machine set-config (list (+ (first config) stack)
                                     (second config)
                                     (third config)))
      (send machine-abst set-config (list (+ (first config) stack)
                                          (second config)
                                          (third config)))
      (set! simulator-abst (new arm-simulator-racket% [machine machine-abst]))
      (set! validator-abst (new arm-validator% [machine machine-abst] [printer printer]))
      (set! inverse (new arm-inverse% [machine machine-abst] [simulator simulator-abst]))
      (set! enum (new arm-enumerative% [machine machine-abst] [printer printer]))
      ;; Set machine to reduced-bidwith machine.
      (set! machine machine-abst))

    (define max-val (arithmetic-shift 1 bit))
    (define mask (sub1 (arithmetic-shift 1 bit)))
    (define mask-1 (sub1 (arithmetic-shift 1 (sub1 bit))))
    (define inst-id (get-field inst-id machine))
    (define cmp-inst
      (map (lambda (x) (vector-member x inst-id))'(cmp tst cmp# tst#)))

    ;; Convert instruction into vector/list/pair format.
    (define (inst->vector x)
      (vector (inst-op x) (inst-args x) (inst-shfop x) (inst-shfarg x) (inst-cond x)))

    ;; Mask in only the live values. If an entry in progstate is not live, set it to #f.
    ;; state-vec: progstate in vector/list/pair format
    ;; live-list: liveness in compact format
    ;; keep-flag: if #f, set flag to default value.
    ;; output: masked progstate in vector/list/pair format
    (define (mask-in state-vec live-list [live-in #f] #:keep-flag [keep #t])
      (define live-reg (first live-list))
      (define live-mem (second live-list))
      
      (define regs (vector-ref state-vec 0))
      (define mems (vector-ref state-vec 1))
      (define z (vector-ref state-vec 2))
      (define fp (vector-ref state-vec 3))

      (define regs-out 
        (for/vector ([r regs] [i (in-naturals)])
                    (and (member i live-reg) r)))

      (when live-in
            (cond
             [(= (third live-in) (third live-list))
              (for ([i (range nregs (+ nregs (third live-in)))])
                   (vector-set! regs-out i (vector-ref regs i)))]
             [else #f]
             ;; [(< (third live-in) (third live-list)) #f]
             ;; [else
             ;;  (let ([diff (- (third live-in) (third live-list))])
             ;;    (for ([i (range nregs (+ nregs (third live-list)))])
             ;;         (vector-set! regs-out i (vector-ref regs (+ diff i)))))]
             ))
              
      (vector
       regs-out
       (for/vector ([m mems] [i (in-naturals)])
		   (and (member i live-mem) m))
       (if keep z -1) fp))

    ;; Extract liveness from programstate. If an entry is a number, then it is live.
    ;; state-vec: progstate in vector/list/pair format
    ;; output: liveness in compact format.
    (define (get-live-mask state-vec)
      (list
       ;; registers
       (filter number?
               (for/list ([i nregs]
                          [r (vector-ref state-vec 0)])
                         (and r i)))
       ;; memory
       (filter number?
               (for/list ([i (in-naturals)]
                          [r (vector-ref state-vec 1)])
                         (and r i)))
       (count number? (vector->list (vector-copy (vector-ref state-vec 0) nregs (+ nregs stack))))
       )
      )
    
    (define (reduce-inst x change)
      (define opcode-name (send machine get-inst-name (inst-op x)))
      (define args (inst-args x))
      (define shfop-name (and (inst-shfop x) (send machine get-shf-inst-name (inst-shfop x))))
      (define shfarg (inst-shfarg x))
      (define types (send machine get-arg-types opcode-name))
      
      (define new-args
        (for/vector
         ([arg args]
          [type types])
         (if (member type '(const op2 bit bit-no-0))
             (change arg type)
             arg)))

      (define new-shfarg
        (if (member shfop-name '(lsr# asr# lsl#))
            (change shfarg `bit)
            shfarg))

      (arm-inst (inst-op x) new-args (inst-shfop x) new-shfarg (inst-cond x)))
    
    (define (reduce-inst-list x change)
      (define opcode-name (send machine get-inst-name (inst-op x)))
      (define args (inst-args x))
      (define shfop-name (and (inst-shfop x) (send machine get-shf-inst-name (inst-shfop x))))
      (define shfarg (inst-shfarg x))
      (define types (send machine get-arg-types opcode-name))
      
      (define new-args
        (for/list
         ([arg args]
          [type types])
         (if (member type '(const op2 bit bit-no-0))
             (change arg type)
             (list arg))))

      (define new-shfarg
        (if (member shfop-name '(lsr# asr# lsl#))
            (change shfarg `bit)
            (list shfarg)))

      (define op (inst-op x))
      (define shfop (inst-shfop x))
      (define cond-type (inst-cond x))

      (define ret (list))
      (define (recurse args-list shfarg-list args-final shfarg-final)
        (cond
         [(equal? shfarg-list #f)
          (set! ret (cons (arm-inst op (list->vector args-final)
                                    shfop shfarg-final cond-type) ret))]
         [(empty? args-list)
          (for ([x shfarg-list])
               (recurse args-list #f args-final x))]

         [else
          (for ([x (car args-list)])
               (recurse (cdr args-list) shfarg-list
                        (cons x args-final) shfarg-final))]))

      (recurse (reverse new-args) new-shfarg (list) #f)
      ret)
    
    ;; Convert input program into reduced-bitwidth program by replacing constants.
    ;; output: a pair of (reduced-bitwidth program, replacement map*)
    ;;   *replacement map maps reduced-bitwidth constants to sets of actual constants.
    (define (reduce-precision prog)
      (define mapping (make-hash))
      (define (change arg type)
        (define (inner)
          (cond
           [(member type '(op2 bit bit-no-0))
            (cond
             [(and (> arg 0) (<= arg (/ bit-precise 4)))
              (/ bit 4)]
             [(and (> arg (/ bit-precise 4)) (< arg (* 3 (/ bit-precise 4))))
              (/ bit 2)]
             [(and (>= arg (* 3 (/ bit-precise 4))) (< arg bit-precise))
              (* 3 (/ bit 4))]
             [(= arg bit-precise) bit]
             [(> arg 0) (bitwise-and arg mask-1)]
             [else (finitize (bitwise-and arg mask) bit)])]

           [(> arg 0) (bitwise-and arg mask-1)]
           [else (finitize (bitwise-and arg mask) bit)]))
        (define ret (inner))
        (if (hash-has-key? mapping ret)
            (let ([val (hash-ref mapping ret)])
              (unless (member arg val)
                      (hash-set! mapping ret (cons arg val))))
            (hash-set! mapping ret (list arg)))
        ret)
        
      (cons (for/vector ([x prog]) (reduce-inst x change)) mapping))
    
    ;; Convert reduced-bitwidth program into program in precise domain.
    ;; prog: reduced bitwidth program
    ;; mapping: replacement map returned from 'reduce-precision' function
    ;; output: a list of potential programs in precise domain
    (define (increase-precision prog mapping)
      (define (change arg type)
        (define (finalize x)
          (if (hash-has-key? mapping arg)
              (let ([val (hash-ref mapping arg)])
                (if (member x val) val (cons x val)))
              (list x)))
        
        (cond
         [(= arg bit) (finalize bit-precise)]
         [(= arg (sub1 bit)) (finalize (sub1 bit-precise))]
         [(= arg (/ bit 2)) (finalize (/ bit-precise 2))]
         [else (finalize arg)]))

      (define ret (list))
      (define (recurse lst final)
        (if (empty? lst)
            (set! ret (cons (list->vector final) ret))
            (for ([x (car lst)])
                 (recurse (cdr lst) (cons x final)))))
      
      (recurse (reverse (for/list ([x prog]) (reduce-inst-list x change)))
               (list))
      ret)

    ;; Analyze if we should include comparing instructions into out instruction pool.
    ;; code: input program
    ;; state: program state in progstate format
    ;; live: live-in information in progstate format
    (define (try-cmp? code state live)
      (define z (progstate-z state))
      (define live-z (progstate-z live))
      (define use-cond1 (for/or ([x code]) (member (inst-op x) cmp-inst)))
      (define use-cond2 (for/or ([x code]) (not (= (inst-cond x) 0))))

      (cond
       [(and live-z (> z -1) use-cond1) 1]
       [(and (> z -1) (or use-cond1 use-cond2)) 2]
       [else 0]))

    ;; Combine livenss information at an abitrary point p in the program.
    ;; x: liveness from executing the program from the beginning to point p.
    ;; y: liveness from analyzing the program backward from the end to point p.
    (define (combine-live x y) 
      ;; Use register's liveness from x but memory's liveness from y.
      (list (first x) (second y) (third x)))

    ;; Sort liveness. Say we have program prefixes that have different live-outs.
    ;; If liveness A comes before B, program prefix with live-out A will be considered before program prefix with live-out B.
    (define (sort-live keys)
      (pretty-display `(sort-live ,keys ,(length keys)))
      (sort keys (lambda (x y)
                   (if (= (third (entry-live x)) (third (entry-live y)))
                       (> (length (first (entry-live x)))
                          (length (first (entry-live y))))
                       (> (third (entry-live x)) (third (entry-live y)))))))

    ;; Similar to 'sort-live' but for backward direction (program postfixes).
    (define (sort-live-bw keys)
      (pretty-display `(sort-live-bw ,keys ,(length keys)))
      (sort keys (lambda (x y)
                   (if (= (third x) (third y))
                       (if (= (length (second x)) (length (second y)))
                           (> (length (first x)) 0)
                           (<= (length (second x)) (length (second y))))
                       (> (third x) (third y))))))

    ))
