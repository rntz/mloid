#lang racket

(require racket/pretty)

(provide
  debug! undebug! toggle-debug!
  debug debugf debugf-pretty)

(define *debug* #t)

(define (debug!) (set! *debug* #t))
(define (undebug!) (set! *debug* #f))
(define (toggle-debug!) (set! *debug* (not *debug*)))

(define-syntax-rule (debug body ...)
  (when *debug* body ...))

(define-syntax-rule (debugf format args ...)
  (debug (eprintf (string-append format "\n") args ...)))

(define-syntax-rule (debugf-pretty format args ... last-arg)
  (debug
    (eprintf (string-append format " ") args ...)
    (pretty-print last-arg (current-error-port) 1)))
