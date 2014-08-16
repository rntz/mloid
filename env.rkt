#lang racket

(require
  (for-syntax
    (only-in racket/set list->set set-member?)
    syntax/parse
    (only-in racket/syntax format-id with-syntax*)))

(require "util.rkt")
(require "values.rkt")

(provide make-ExtPoint define-ExtPoint ExtPoint-equal?)

(define (make-ExtPoint name join empty)
  (ExtPoint name (gensym name) (Monoid join empty)))

(define-syntax (define-ExtPoint stx)
  (with-syntax* ([(_ name join empty) stx]
                 [name-join  (format-id #'name "~a-join" #'name)]
                 [name-empty (format-id #'name "~a-empty" #'name)])
    #`(begin
        (define name (make-ExtPoint 'name join empty))
        (define name-join (ExtPoint-join name))
        (define name-empty (ExtPoint-empty name)))))

(define ExtPoint-equal?
  (lambda (x y) (eq? (ExtPoint-uid x) (ExtPoint-uid y)))
  ;(match-lambda** [((ExtPoint _ uid1 _) (ExtPoint _ uid2 _)) (eq? uid1 uid2)])
  )


;; Environments are immutable hashtables, mapping extension-points to their
;; monoid values. If an extension-point is absent, it is the same as being
;; mapped to its empty value.

(provide env-empty env-join2 env-join* env-join env-monoid env-single env-get)

;; hashtable type used for extension-point envs. I don't think this is
;; necessary, since racket *can* hash functions, and we never intend to generate
;; two ExtPoints with the same uid.
;;
;; (define-custom-hash-types ext-hash
;;   #:key? ExtPoint?
;;   ExtPoint-equal?
;;   (lambda (x) (eq-hash-code (ExtPoint-uid x)))
;;   (lambda (x) (equal-secondary-hash-code (ExtPoint-uid x))))

(define env-empty (hash))

(define (env-join2 a b)
  (hash-union a b (lambda (k x y) ((ExtPoint-join k) x y))))

(define (env-join* es) (reduce es env-empty env-join2))

(define (env-join . es) (env-join* es))

(define env-monoid (Monoid env-join2 env-empty))

(define (env-single ext-point value)
  (hash ext-point value))

(define (env-get ext-point env)
  (hash-get ext-point env
    (lambda () (ExtPoint-empty ext-point))))


;; Tools for defining interfaces on hashes and convenient ways to construct
;; hashes. We use hashes to represent records (and thus, more or less, OO-style
;; objects) in our language. Methods are represented by keys mapped to
;; functions; properties by keys mapped to values.
;;
;; FIXME: factor this out into its own file.

(provide define-iface define-accessors define-accessor define-form record)

(define-for-syntax (make-define-form stx form fields ifaces methods)
  (with-syntax ([form form]
                [(field ...) fields]
                [(iface ...) ifaces]
                [(method ...) methods])
    (define (method-name a)
        (if (pair? a) (car a) a))
      (define fields (syntax->datum #'(field ...)))
      (define methods (map (compose method-name car)
                        (syntax->datum #'(method ...))))
      (define all-methods (list->set (append fields methods)))
      (for* ([ifc (syntax->list #'(iface ...))]
             [m (map method-name (syntax-local-value ifc))])
        (unless (set-member? all-methods m)
          (raise-syntax-error #f (format "method ~v not implemented" m) stx)))
      #`(define (form field ...)
          (record
            [#,'form 'form]
            [field field] ...
            method ...))))

(define-syntax (define-iface stx)
  (syntax-parse stx
    [(_ iface-name accessor ...)
      #`(begin
          (define-syntax iface-name '(accessor ...))
          (define-accessors iface-name accessor ...)
          (define-syntax (#,(format-id #'iface-name "define-~a" #'iface-name)
                           stx)
            (syntax-parse stx
              [(_ form-name:id (field:id (... ...)) method (... ...))
                (make-define-form stx
                  (format-id #'form-name "~a:~a" #'iface-name #'form-name)
                  #'(field (... ...))
                  #'(iface-name)
                  #'(method (... ...)))])))]))

(define-syntax (define-accessors stx)
  (syntax-parse stx
    [(_ prefix:id accessor ...)
      (let ([mk-name (lambda (name)
                       (format-id #'prefix "~a-~a" #'prefix name))])
        #`(begin
            #,@(for/list [(axor (syntax->list #'(accessor ...)))]
                 (syntax-parse axor
                   [(name:id param:id ...)
                     #`(define-accessor #,(mk-name #'name) name (param ...))]
                   [name:id
                     #`(define-accessor #,(mk-name #'name) name)]))))]))

(define-syntax (define-accessor stx)
  (syntax-parse stx
    [(_ axor-name:id key:id)
      #`(define (axor-name self [or-else #f])
          (hash-get 'key self (or or-else (lambda () (error 'axor-name
                                                  "absent field: ~v" 'key)))))]
    [(_ axor-name:id key:id (param:id ...))
      #`(define (axor-name self param ...)
          ((hash-get 'key self (lambda ()
                                 (error 'axor-name "absent method: ~v" 'key)))
            param ...))]))

(define-syntax (define-form stx)
  (syntax-parse stx
    [(_ form (field:id ...) #:isa (iface:id ...) method ...)
      (make-define-form stx #'form #'(field ...) #'(iface ...) #'(method ...))]
    [(_ form (field:id ...) #:isa iface:id method ...)
      (make-define-form stx #'form #'(field ...) #'(iface) #'(method ...))]
    [(_ form (field:id ...) method ...)
      (make-define-form stx #'form #'(field ...) #'() #'(method ...))]))

(define-syntax (record stx)
  (let* ([bindings (cdr (syntax->list stx))]
         [names (map (lambda (b) (syntax-parse b
                              [(name:id value) #'name]
                              ;; TODO: must have at least one body expr
                              [((name:id param:id ...) body ...) #'name]))
                  bindings)]
         [exprs (map (lambda (b) (syntax-parse b
                              [(name:id value) #'value]
                              [((name:id param:id ...) body ...)
                                #'(lambda (param ...) body ...)]))
                  bindings)])
    (with-syntax ([(name ...) names] [(expr ...) exprs])
      #`(make-immutable-hash
          (let* ((name expr) ...)
            `((name . ,name) ...))))))


;; -- Built-in ParseEnv extension points --
;; Convention: extension point names begin with "@"

(provide
  @exprs @exprs-join @exprs-empty
  define-@expr @expr @expr-parser

  ;; TODO: rename to @infix-exprs
  @infixes @infixes-join @infixes-empty
  define-@infix @infix @infix-precedence @infix-parser

  @pats @pats-join @pats-empty
  define-@pat @pat @pat-parser

  ;; TODO: unify @infix-exprs & @infix-pats somehow?
  @infix-pats @infix-pats-join @infix-pats-empty
  define-@infix-pat @infix-pat @infix-pat-precedence @infix-pat-parser

  @decls @decls-join @decls-empty
  define-@decl @decl @decl-parser

  @tops @tops-join @tops-empty
  define-@top @top @top-parse-eval)

;; Maps tokens to (@expr)s
(define-ExtPoint @exprs hash-union (hash))
(define-iface @expr
  parser     ;; Parser Expr
  )

;; Maps tokens to (@infix)es
(define-ExtPoint @infixes hash-union (hash))
(define-iface @infix
  precedence               ;; Int
  ;; parser : Expr -> Parser Expr
  ;; takes the "left argument" to the infix operator.
  ;; needs to parse the right argument(s) itself.
  ;; so this really allows any non-prefix operator, not just infix
  ;; (postfix or ternary operators, for example)
  (parser left-expr))

;; Maps tokens to (@pat)s
(define-ExtPoint @pats hash-union (hash))
(define-iface @pat
  parser) ;; Parser Pat

(define-ExtPoint @infix-pats hash-union (hash))
(define-iface @infix-pat
  precedence               ;; Int
  ;; parser : Expr -> Parser Expr, see @infix-parser above for explanation
  (parser left-pat))

;; Maps tokens to (@decl)s.
(define-ExtPoint @decls hash-union (hash))
(define-iface @decl
  parser ;; Parser Decl (see "parts of speech" below for what Decl is)
  )

;; Maps tokens to (@top)s.
(define-ExtPoint @tops hash-union (hash))
(define-iface @top
  ;; ResolveEnv, NS -> Parser Result
  ;; ns is the Racket namespace in which we eval code.
  (parse-eval resolve-env ns))


;; -- Built-in ResolveEnv extension points --

;; TODO: should ResolveEnv really be represented as an env? or is it too
;; special-purpose? What legitimate extensions to ResolveEnv are possible?

(provide
  @vars @vars-join @vars-empty
  define-@var @var @var-style @var-id @var-tag-id @var-tag-params @var-tag-arity
  @var:var @var:ctor @vars-var @vars-ctor)

;; maps var names to hashes of info about them.
;; hash keys:
;; - style: one of '(var ctor)
;; - id: the IR identifier for the value of this variable.
;;
;; Hash keys for ctors:
;; - tag-id: The IR id for the tag for this ctor.
;; - tag-params: (Maybe [Symbol]). The parameters for the ctor, if any.
(define-ExtPoint @vars hash-union (hash))

(define-iface @var style id)
(define-accessors @var tag-id tag-params) ;not-always-present fields

(define (@var-tag-arity v [or-else #f])
  (maybe (@var-tag-params v) 0 length))

;; TODO: should this go here, in core-forms.rkt, or in parse-builtins.rkt?
(define-@var var (name id) [style 'var])
(define-@var ctor (name id tag-id tag-params) [style 'ctor])

(define (@vars-var name id) (hash name (@var:var name id)))
(define (@vars-ctor name id tag-id tag-params)
  (hash name (@var:ctor name id tag-id tag-params)))


;; Builtin parts of speech.
;;
;; "Parts of speech" are interfaces for various parts of the language AST; e.g.
;; expressions, declarations, patterns.
;;
;; Parts of speech are defined by the interface they present so that people can
;; add new forms with new behavior. E.g. an Expr is anything that has a 'compile
;; "method" that takes a ResolveEnv and produces an IR expression.

(provide
  define-expr expr expr-compile expr-sexp
  define-decl decl decl-sexp decl-resolveExt decl-compile
  define-pat pat pat-sexp pat-resolveExt pat-idents pat-compile
  define-result result result-resolveExt result-parseExt
  define-nodule nodule nodule-name nodule-resolveExt nodule-parseExt)

(define-iface expr
  (sexp)
  (compile resolve-env))                ; ResolveEnv -> IR

(define-iface decl
  (sexp)
  parseExt                              ; ParseEnv
  resolveExt                            ; ResolveEnv

  ;; The rest of our interface would ideally be:
  ;;
  ;;   idents: [Id]
  ;;   compile: ResolveEnv -> IR
  ;;
  ;; where `idents' is a list of the identifiers bound, and (compile env)
  ;; returns code which evaluates to a "tuple" of the values each identifier
  ;; should have. Practically, however, this requires either (a) allocating a
  ;; tuple or (b) using multiple-return-values. I'd like to avoid (a) because it
  ;; sucks and (b) because it's very racket-specific (if we designed our own IR
  ;; it would be difficult to duplicate - MRV is hard to implement efficiently).
  ;;
  ;; Also it makes it slightly harder to define mutually recursive functions.
  ;;
  ;; So instead we do this:
  ;;
  ;;   compile: ResolveEnv -> [(Id, IR)]
  ;;
  ;; Returns a list of identifier-IR pairs, (id code). `code' is IR that
  ;; evaluates to what `id' should be bound to. Each `id' is in the scope of
  ;; every `code', but the `id's are defined in the order given (a la letrec).
  (compile resolve-env))

(define-iface pat
  (sexp)
  ;; can patterns really modify our resolve environment in arbitrary ways?
  ;;
  ;; relatedly: how do I know what identifiers a pattern binds (say I need to
  ;; use it in a val decl, say)?
  resolveExt                            ; ResolveEnv

  ;; The rest of our interface would ideally be something like:
  ;;
  ;;   idents: [Id]
  ;;   compile: ResolveEnv, IR -> IR
  ;;
  ;; Where `idents' is a list of identifiers bound, and (compile env subject)
  ;; returns code that matches against `subject' and evaluates to either (Just
  ;; t) where `t' is a tuple of the values the `idents' should be bound to, or
  ;; None, indicating pattern-match failure.
  ;;
  ;; But this always requires allocating, which sucks. So instead we do this:
  ;;
  ;;   idents: [Id]
  ;;   compile: ResolveEnv, IR, IR, IR -> IR
  ;;
  ;; Where (compile env subject on-success on-failure) returns code that matches
  ;; against `subject', binds the identifiers in `idents' and runs `on-success';
  ;; on pattern-match failure, it runs `on-failure' (it may have bound none,
  ;; some, or all of `idents').
  ;;
  ;; `subject', `on-success' and `on-failure' may occur many times in the
  ;; returned code. So they should be small (e.g. literals, identifiers or
  ;; zero-argument calls to identifiers), and `subject' must be
  ;; side-effect-less.
  ;;
  ;; EDIT: for now I'm letting `on-success' be large. This shouldn't be a
  ;; problem except with patterns that can succeed in multiple ways (e.g.
  ;; or-patterns). So once I implement those I'll reconsider this.
  idents                                ;[Id], represented as a racket list
  (compile resolve-env subject on-success on-failure))

;; The "result" of parsing a top-level declaration. Not exactly a part of
;; speech, but acts like one.
(define-iface result
  resolveExt
  parseExt)

(define-iface nodule ;; can't use "module", it means something in Racket
  name
  resolveExt
  parseExt)
