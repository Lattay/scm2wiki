;; (c) 2020 Michael Neidel
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; # SEMANTICS2MD-IMPL
;;; Low-level implementation for semantics2md

(module semantics2md-impl
    *
  (import scheme (chicken base) (chicken module) (chicken string)
	  srfi-1 srfi-13)

  (define (make-code-block str)
    (string-append "\n```Scheme\n" str "\n```\n\n"))

  (define (make-inline-code-block str)
    (string-append "`"
		   (string-translate str #\newline #\space)
		   "`"))

  ;; Extract documentation for the aspect given by `aspect-key` from the
  ;; **semantic** source element. Returns an empty string if `semantic` does
  ;; not contain the given aspect.
  (define (aspect->string aspect-key semantic)
    (or (alist-ref aspect-key (cdr semantic)) ""))

  (define (type-annotation->string definition)
    (if (alist-ref 'type-annotation (cdr definition))
	(string-append "type: "
		       (alist-ref 'type (alist-ref 'type-annotation
						   (cdr definition)))
		       ", ")
	""))

  (define (transform-generic-definition d)
    (string-append "### "
		   (if (eqv? 'constant-definition (car d))
		       "[CONSTANT] "
		       "[VARIABLE] ")
		   (aspect->string 'name d)
		   "\n```Scheme\n"
		   (aspect->string 'name d)
		   "  ; "
		   (type-annotation->string d)
		   (if (eqv? 'constant-definition (car d))
		       "value: "
		       "default: ")
		   (aspect->string 'value d)
		   "\n```\n"
		   (aspect->string 'comment d)))

  (define (transform-procedure-definition d)
    (string-append "### [PROCEDURE] "
		   (aspect->string 'name d)
		   "\n```Scheme\n"
		   (aspect->string 'signature d)
		   (if (alist-ref 'type-annotation (cdr d))
		       (string-append
			"  ; type: "
			(alist-ref 'type (alist-ref 'type-annotation (cdr d))))
		       "")
		   "\n```\n"
		   (aspect->string 'comment d)))

  (define (string-max-lengths rows)
    (map (lambda (pos)
	   (apply max (map (lambda (row)
			     (string-length (list-ref row pos)))
			   rows)))
	 (iota (length (car rows)))))

  (define (make-md-table header contents)
    (let* ((aspects (filter (lambda (feature)
			      (any (lambda (c)
				     (alist-ref feature (cdr c)))
				   contents))
			    header))
	   (md-header (map ->string aspects))
	   (md-body (map (lambda (c)
			   (map (lambda (a)
				  (let ((astring (aspect->string a c)))
				    (if (string-null? astring)
					""
					(make-inline-code-block astring))))
				aspects))
			 contents))
	   (cell-widths (string-max-lengths (cons md-header md-body))))
      (if (= 1 (length md-header))
	  (string-append (car md-header) ": " (caar md-body) "\n\n")
	  (string-append
	   "\n"
	   (string-intersperse
	    (map (lambda (row)
		   (string-intersperse (map (lambda (cell cell-width)
					      (string-pad-right cell cell-width))
					    row cell-widths)
				       " | "))
		 (append (list md-header (map (lambda (cell-width)
						(make-string cell-width #\-))
					      cell-widths))
			 md-body))
	    "\n")
	   "\n"))))

  (define (transform-record-definition d)
    (string-append "### [RECORD] "
		   (aspect->string 'name d)
		   "\n\n**constructor:** "
		   (make-inline-code-block (aspect->string 'constructor d))
		   "  \n**predicate:** "
		   (make-inline-code-block (aspect->string 'predicate d))
		   "  \n**implementation:** "
		   (make-inline-code-block (aspect->string 'implementation d))
		   "  \n**fields:**\n"
		   (make-md-table '(name getter setter default type comment)
				  (alist-ref 'fields (cdr d)))
		   "\n"
		   (aspect->string 'comment d)
		   "\n"))

  ;; TODO extract the signature
  (define (transform-syntax-definition d)
    (string-append "### [SYNTAX] "
		   (aspect->string 'name d)
		   "\n"
		   (aspect->string 'comment d)))

  (define (transform-class-definition d)
    (string-append "### [CLASS] "
		   (make-inline-code-block (aspect->string 'name d))
		   "  \n**inherits from:** "
		   (string-concatenate (map make-inline-code-block
					    (alist-ref 'superclasses (cdr d))))
		   "  \n**slots:**\n"
		   (make-md-table '(name initform accessor getter setter)
				  (alist-ref 'slots (cdr d)))
		   "\n"
		   (aspect->string 'comment d)
		   "\n"))

  (define (transform-module-declaration d document-internals)
    (string-append "## MODULE "
		   (aspect->string 'name d)
		   "\n"
		   (aspect->string 'comment d)
		   "\n"
		   (string-intersperse
		    (map (lambda (elem)
			   (transform-source-element elem
						     document-internals))
			 (if document-internals
			     (alist-ref 'body (cdr d))
			     ;; TODO filter against exports list
			     (alist-ref 'body (cdr d))))
		    "\n\n")))

  (define (transform-source-element source-element document-internals)
    (case (car source-element)
      ((comment) (cdr source-element))
      ((constant-definition variable-definition)
       (transform-generic-definition source-element))
      ((module-declaration) (transform-module-declaration source-element
							  document-internals))
      ((procedure-definition) (transform-procedure-definition source-element))
      ((record-definition) (transform-record-definition source-element))
      ((syntax-definition) (transform-syntax-definition source-element))
      ((class-definition) (transform-class-definition source-element))
      (else (error (string-append "Unsupported source element "
				  (->string (car source-element)))))))

  ;;; Generate documentation in Markdown format from  a semantic **source**
  ;;; expression (as produced by parse-semantics from the scm-semantics module).
  ;;; If the source contains a module declaration, only exported symbols will be
  ;;; included in the resulting documentation, unless **document-internals** is
  ;;; set to `#t`.
  (define (semantics->md source #!optional document-internals)
    (unless (eqv? 'source (car source))
      (error "Not a semantic source expression."))
    (string-append (string-intersperse
		    (map (lambda (elem)
			   (transform-source-element elem document-internals))
			 (cdr source))
		    "\n")
		   "\n"))

  ) ;; end module semantics2md-impl
