#lang racket

(require "GA-parser.rkt"
         "main.rkt")

(define size (make-parameter #f))
(define cores (make-parameter 12))
(define search-type (make-parameter `hybrid))
(define mode (make-parameter `syn))
(define dir (make-parameter "output"))
(define time-limit (make-parameter 3600))
 
(define file-to-optimize
  (command-line
   #:once-each
   [("-c" "--core")      c
                        "Number of cores to run on (default=12)"
                        (cores (string->number c))]
   [("-d" "--dir")      d
                        "Output directory (default=output)"
                        (dir d)]
   [("-t" "--time-limit") t
                        "Time limit in seconds (default=36000)."
                        (time-limit t)]
   [("-n" "--size")     n
                        "Time limit in seconds (default=36000)."
                        (size n)]
   [("-i" "--input")    i
                        "Path to inputs."
                        (input-file i)]

   #:once-any
   [("--solver") "Use solver-based search."
                        (search-type `solver)]
   [("--stoch") "Use stochastic search."
                        (search-type `stoch)]
   [("--hybrid") "Use stochastic search."
                        (search-type `hybrid)]

   #:once-any
   [("-l" "--linear")   "Linear search."
                        (mode `linear)]
   [("-b" "--binary")   "Binary search."
                        (mode `binary)]

   #:once-any
   [("-o" "--optimize") "Optimize mode starts searching from the original program"
                        (mode `opt)]
   [("-s" "--synthesize") "Synthesize mode starts searching from random programs (default)"
                        (mode `syn)]


   #:args (filename) ; expect one command-line argument: <filename>
   ; return the argument as a filename to compile
   filename))

(define parser (new GA-parser%))
(define code (send parser ast-from-file file-to-optimize))
(define-values (live-out recv assume input-file) (send parser info-from-file (string-append file-to-optimize ".info")))

(pretty-display `(live-out ,live-out ,recv  ,assume ,input-file))
(optimize code live-out (search-type) (mode) recv
	  #:assume assume
          #:need-filter #f #:dir (dir) #:cores (cores) 
          #:time-limit (time-limit) #:size (size)
          #:input-file input-file
	  )