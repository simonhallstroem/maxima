; macros.l - all the basic macros
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;Copyright (c) University of Waikato;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;Hamilton, New Zeland 1992-95 - all rights reserved;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :f2cl-lib)

; macros:
;	rexpt
;	fexport
;	fproclaim
;	fuse-package 
;	fin-package
;	map-defvar
;	do1 
;	do!
;	double-cdr
;	putproperty
;	defprop
;	array-cl
;	store-cl
;	apply!

;	rfref
;	rfset
;	fref
;	fset

;	while
;       fdo
;	reset-vble - a defun
;       arithmetic-if
;	computed-goto
;	assigned-goto
;	eqv
;	constant-list
;----------------------------------------------------------------------------

(eval-when (compile load eval) (proclaim '(special *verbose*)))
;----------------------------------------------------------------------------
#+aclpc (defmacro rexpt (x y) `(realpart (expt ,x ,y)))
#-aclpc (defmacro rexpt (x y) `(expt ,x ,y))

(defvar *check-array-bounds* nil
  "If non-NIL, generated code checks for array bounds.  If NIL, checking
is not included")

;;------------------------------------------------------------------------------
;;
;; Define the equivalent types between Fortran and Lisp.  This MUST
;; match the types given in f2cl1.l so keep it in sync!
(deftype logical ()
  `(member t nil))

;; Decide what you want integer*4 to be.  Good choices are fixnum or
;; (signed-byte 32).  The latter is good only if your compiler does a
;; good job with this type.  If you aren't sure, use fixnum.  CMUCL
;; does a good job with (signed-byte 32).
;;
;; If you change this, you may need to change some of the macros
;; below, such as INT and AINT!

#+cmu
(deftype integer4 ()
  `(signed-byte 32))
#-cmu
(deftype integer4 ()
  'fixnum)

(deftype integer2 ()
  `(signed-byte 16))
(deftype integer1 ()
  `(signed-byte 8))
(deftype real8 ()
  'double-float)
(deftype real4 ()
  'single-float)
(deftype complex8 ()
  `(complex single-float))
(deftype complex16 ()
  `(complex double-float))

(deftype array-double-float ()
    `(array double-float (*)))
(deftype array-integer4 ()
    `(array integer4 (*)))
(deftype array-single-float ()
    `(array single-float (*)))
(deftype array-strings ()
  `(array string (*)))

(defconstant %false% nil)
(defconstant %true% t)
;;------------------------------------------------------------------------------

;;-----------------------------------------------------------------------------

;; Array dimensions are (d1, d2, d3, ...)
;;
;; Then x(n1, n2, n3, ...) means index is
;;
;; n1 + d1*(n2 + d2*(n3 + d3*(n4 + d4*(n5))))

;; Return an expression that computes the column major index given the
;; indices and the bounds on each dimension.  The bounds are a list of
;; the upper and lower bounds for each dimension.
(defun col-major-index (indices dims)
  (flet ((get-offset (n bound)
	   (let ((lo (first bound)))
	     (if (and (numberp lo) (zerop lo))
		 n
		 `(the fixnum (- (the fixnum ,n) (the fixnum ,lo))))))
	 (get-size (bound)
	   (destructuring-bind (lo hi)
	       bound
	     (cond ((numberp lo)
		    (cond ((numberp hi)
			   (1+ (- hi lo)))
			  ((= lo 1)
			   hi)
			  (t
			   `(- ,hi ,(- lo 1)))))
		   (t
		    `(the fixnum (- ,hi (the fixnum (- (the fixnum ,lo) 1)))))))))
    (let* ((rev-idx (reverse indices))
	   (rev-dim (reverse dims))
	   (idx (get-offset (first rev-idx) (first rev-dim))))
      (do ((d (rest rev-dim) (rest d))
	   (n (rest rev-idx) (rest n)))
	  ((endp d)
	   idx)
	(setf idx `(the fixnum (+ ,(get-offset (first n) (first d))
				  (the fixnum (* ,(get-size (first d)) ,idx)))))))))

(defun check-array-bounds (indices bounds)
  `(and ,@(mapcar #'(lambda (idx dim)
		     `(<= ,(first dim) ,idx ,(second dim)))
		 indices bounds)))

(defmacro fref (arr indices bounds &optional offset)
  (if *check-array-bounds*
      `(aref ,arr (if ,(check-array-bounds indices bounds)
		      (the fixnum (+ (the fixnum ,(or offset 0)) ,(col-major-index indices bounds)))
		      (error "Out of bounds index for array ~S"
			     ',arr)))
      `(aref ,arr (the fixnum (+ (the fixnum ,(or offset 0)) ,(col-major-index indices bounds))))))

(defmacro fset (a b) 
  `(setf (fref ,(second a) ,@(cddr a)) ,b))

(defmacro fref-string (s range)
  `(subseq ,s (1- ,(first range)) ,(second range)))

(defmacro fset-string (a b)
  `(setf (fref-string ,(second a) ,(third a)) ,b))

(defmacro f2cl-// (a b)
  `(concatenate 'string ,a ,b))

;; (with-array-data ((data-var offset-var array))
;;   ...
;; )

(defun find-array-data (array)
  (declare (type (array * (*)) array))
  (let ((offset 0))
    (declare (type fixnum offset)
	     (optimize (speed 3) (safety 0)))
    (loop
	(multiple-value-bind (displaced-to index-offset)
	    (array-displacement array)
	  (when (null displaced-to)
	    (return-from find-array-data (values array offset)))
	  (incf offset index-offset)
	  (setf array displaced-to)))))

(defmacro with-array-data ((data-var offset-var array) &rest body)
  `(multiple-value-bind (,data-var ,offset-var)
    (find-array-data ,array)
    ,@body))

;; Create an array slice for the array named VNAME whose elements are
;; of type TYPE.  The slice starts at the indices INDICES and the
;; original array has dimensions given by BOUND.
;;
;; This is done by making a displaced array to VNAME with the
;; appropriate offset.
#+nil
(defmacro array-slice (vname type indices bounds)
  (let ((dims `(* ,@(mapcar #'(lambda (idx bnd)
				(if (and (numberp idx)
					 (numberp (second bnd)))
				    (+ (- (second bnd) idx) 1)
				    `(+ (- ,(second bnd) ,idx) 1)))
			    indices bounds))))
    `(make-array ,dims
      :element-type ',type
      :displaced-to ,vname
      :displaced-index-offset ,(col-major-index indices bounds))))

(defmacro array-slice (vname type indices bounds)
  ;; To figure the size of the sliced array, use ARRAY-TOTAL-SIZE
  ;; instead of the f2cl derived/declared BOUNDS, just in case we
  ;; screwed up or in case we changed the size of the array in some
  ;; other way.  This isn't possible in a function, but the array
  ;; might be in a common block and we could change the dimensions of
  ;; the common block at runtime.  (Some Fortran code like mpfun does
  ;; this, although it's actually illegal.  Neat hack to "dynamically"
  ;; change the dimensions.  Of course, for this to work in Fortran,
  ;; the common block has to contain exactly that one array, or the
  ;; array must be the last element of the common block.)
  `(make-array (- (array-total-size ,vname) ,(col-major-index indices bounds))
    :element-type ',type
    :displaced-to ,vname
    :displaced-index-offset ,(col-major-index indices bounds)))

#+nil
(defmacro array-slice (vname type indices bounds)
  (declare (ignore type indices bounds))
  vname)

;; Compute an initializer for make-array given the data in the list
;; DATA.  The array has en element type of TYPE and has dimensions of
;; DIMS.
(defmacro array-initialize (type dims data)
  (let ((data-list (gensym))
	(data-len (length data))
	(total-length (gensym)))
    `(let* ((,data-list ',data)
	    (,total-length (reduce #'* (list ,@dims))))
       (cond ((< ,data-len ,total-length)
	      ;; Need to append some data.
	      (append ,data-list (make-list (- ,total-length ,data-len)
					    :initial-element (coerce 0 ',type))))
	     ((> ,data-len ,total-length)
	      ;; Need to truncate some data
	      (subseq ,data-list 0 ,total-length))
	     (t
	      ,data-list)))))  

;----------------------------------------------------------------------------

#-aclpc (defmacro while (con &rest body)
            `(loop (if (not ,con) (return t)) ,@body))
;------------------------------------------------------------------

(defmacro fortran_comment (&rest args)
  (declare (ignore args)))

;----------------------------------------------------------------------------
; fdo has similar syntax as do except there will only be one do_vble

(defmacro fdo (do_vble_clause predicate_clause &rest body)
  (let ((step (gensym "STEP-"))
	(iteration_count (gensym "CNT-")))
    `(prog* ((,step ,(third (third do_vble_clause)))
	     (,iteration_count 
	      (max 0 (the integer4
		       (truncate (the integer4
				   (+ (the integer4 (- ,(third (first predicate_clause))
						       ,(second do_vble_clause)))
				      ,step))
				 ,step))
		   )))
      (declare (type integer4 ,step ,iteration_count))
      ;; initialise loop variable
      (setq ,(first do_vble_clause) ,(second do_vble_clause))
      loop
      (return
	(cond				; all iterations done
	  ((zerop ,iteration_count) nil)
	  ;; execute loop, in/de-crement loop vble and decrement cntr
	  ,(cons 't 
		 (append 
		  (append body
			  `((setq ,(first do_vble_clause) (the integer4 ,(third do_vble_clause))
			     ,iteration_count (the integer4 (1- ,iteration_count)))))
		  '((go loop)))))))))

;(defmacro fdo (do-vbles predicate-clause &rest body)
;   `(prog nil
;          (setq ,(caar do-vbles) ,(cadar do-vbles)) 
;          loop
;          (return
;          (cond ,(reset-vble predicate-clause)
;                ,(cons 't 
;                       (append 
;                        (append body `((setq ,(caar do-vbles) ,(caddar do-vbles))))
;                        '((go loop))))))))
;(defmacro fdo (do-vbles predicate-clause &rest body)
;   `(prog (iteration-count)
;          ,(append '(psetq) 
;                   (do ((do-vars do-vbles (cdr do-vars))
;                        (ret nil (append ret (list (caar do-vars) (cadar do-vars)))))
;                       ((null do-vars) ret)))
;          loop
;          (return
;          (cond ,predicate-clause
;                ,(cons 't 
;                       (append 
;                        (append body
;                                (list
;                                (append '(psetq)
;                                (do ((do-vars do-vbles (cdr do-vars))
;                                     (ret nil (append ret (if (null (caddar do-vars)) 
;                                                              nil 
;                                                              (list (caar do-vars) 
;                                                                    (caddar do-vars))))))
;                                    ((null do-vars) ret)))))
;                        '((go loop))))))))

;----------------------------------------------------------------------------
;; macro for division 

(defmacro f2cl/ (x y)
  (let ((top (gensym))
	(bot (gensym)))
    `(let ((,top ,x)
	   (,bot ,y))
      (if (and (typep ,top 'integer)
	       (typep ,bot 'integer))
	  (values (the integer4 (truncate ,top ,bot)))
	  (/ ,top ,bot)))))

(defmacro int-add (arg &rest more-args)
  (if (null more-args)
      arg
      (if (> (length more-args) 1)
	  `(the integer4 (+ ,arg (int-add ,@more-args)))
	  `(the integer4 (+ ,arg ,@more-args)))))

(defmacro int-sub (arg &rest more-args)
  (if (null more-args)
      `(the integer4 (- ,arg))
      (if (> (length more-args) 1)
	  `(the integer4 (- ,arg (int-sub ,@more-args)))
	  `(the integer4 (- ,arg ,@more-args)))))

(defmacro int-mul (arg &rest more-args)
  (if (null more-args)
      arg
      (if (> (length more-args) 1)
	  `(the integer4 (* ,arg (int-mul ,@more-args)))
	  `(the integer4 (* ,arg ,@more-args)))))


;; macro for a lisp equivalent of Fortran arithmetic IFs
(defmacro arithmetic-if (pred s1 s2 s3)
  (let ((tst (gensym)))
    `(let ((,tst ,pred))
      (cond ((< ,tst 0) ,s1)
	    ((= ,tst 0) ,s2)
	    (t ,s3)))))

;; macro for a lisp equivalent of Fortran computed GOTOs
(defun computed-goto-aux (tags)
  (let ((idx 0)
	(result '()))
    (dolist (tag tags (nreverse result))
      (incf idx)
      (push `(,idx (go ,tag)) result))))

(defmacro computed-goto (tag-lst i)
  `(case ,i
    ,@(computed-goto-aux tag-lst)))

;; macro for a lisp equivalent of Fortran assigned GOTOs
(defmacro assigned-goto (i &optional tag-lst)
   `(if ,tag-lst
        (if (member ,i ,tag-lst) 
            (go ,i)
            (error "bad statement number in assigned goto"))
        (go ,i)))

;;-----------------------------------------------------------------------------
;;
;; Define the intrinsic functions
;;
;; Reference:  The Fortran 77 standard found at www.fortran.com.  Section 15.10

;; INT is the generic name as well as the integer version.  IFIX is
;; the same.  IDINT is the double version.

(declaim (inline int ifix idfix))

#-cmu
(defun int (x)
  ;; We use fixnum here because f2cl thinks Fortran integers are
  ;; fixnums.  If this should change, we need to change the ranges
  ;; here as well.
  (etypecase x
    (integer
     (the integer4 x))
    (single-float
     (truncate (the (single-float #.(float most-negative-fixnum)
				  #.(float most-positive-fixnum))
		 x)))
    (double-float
     (truncate (the (double-float #.(float most-negative-fixnum 1d0)
				  #.(float most-positive-fixnum 1d0))
		 x)))))

#+cmu
(defun int (x)
  ;; For CMUCL, we support the full 32-bit integer range, so INT can
  ;; return a full 32-bit integer.  Tell CMUCL that this is true so we
  ;; generate fast code.  If this is not true, the original Fortran
  ;; code was wrong.
  (etypecase x
    (integer
     (the integer4 x))
    (single-float
     (the integer4
       (truncate (the (single-float #.(float (- (ash 1 31)))
				    #.(float (1- (ash 1 31))))
		   x))))
    (double-float
     (the integer4
       (truncate (the (double-float #.(float (- (ash 1 31)) 1d0)
				    #.(float (1- (ash 1 31)) 1d0))
		   x))))))
  
(defun ifix (x)
  (int x))
(defun idfix (x)
  (int x))

;; AINT is the generic and specific function for real; DINT, for
;; double.  It truncates its arg towards zero and returns the integer
;; as a floating-point number of the same type as its arg.
;;
;; ANINT is the generic and specific function for real; DNINT, for
;; double. It rounds to the nearest integer and returns the result as
;; a float of the same type.
;;
;; NINT is the generic and specific function for real; IDNINT, for
;; double.  Does the same as ANINT, but the result is an integer.

(declaim (inline aint dint anint dnint nint idnint))

(defun aint (x)
  ;; ftruncate is exactly what we want.
  (etypecase x
    (single-float
     (ftruncate (the single-float x)))
    (double-float
     (ftruncate (the double-float x)))))

(defun dint (x)
  (aint x))

(defun anint (x)
  (values (fround x)))
(defun dnint (x)
  (values (fround x)))
(defun nint (x)
  (values (round x)))
(defun idnint (x)
  (values (round x)))

;; Type conversion
;;
;; FREAL is F2CL's version of the Fortran REAL which takes converts
;; its arg to a real.  SNGL is the same.  DBLE returns a double.  They
;; also return the real part of a complex number.  CMPLX takes one or
;; two args and creates a complex number.

(declaim (inline freal sngl dble cmplx))
(defun freal (x)
  (coerce (realpart x) 'single-float))

(defun sngl (x)
  (coerce (realpart x) 'single-float))

(defun dble (x)
  (coerce (realpart x) 'double-float))

(defun cmplx (x &optional y)
  (complex x (if y y 0)))

(defun ichar (c)
  (char-int c))
(defun fchar (i)			;intrinsic function char
  (char-int i))

(declaim (inline iabs dabs cabs amod dmod))
#-aclpc
(defun iabs (x)
  (declare (type integer4 x))
  (abs x))
(defun dabs (x)
  (declare (type double-float x))
  (abs x))
(defun cabs (x)
  (declare (type complex x))
  (abs x))

(defun amod (x y)
  (declare (type single-float x y))
  (mod x y))
(defun dmod (x y)
  (declare (type double-float x y))
  (mod x y))


;; Transfer of sign.  SIGN is the generic and specific function for
;; real.  ISIGN is for integers; DSIGN for doubles.  Basically
;; computes sign(a2)*|a1|.

(declaim (inline isign sign dsign))

(defun isign (x y)
  (declare (type integer4 x y))
  (if (>= y 0)
      (the integer4 (abs x))
      (the integer4 (- (the integer4 (abs x))))))

;; Fortran 77 says SIGN is a generic!
(defun sign (x y)
  (declare (type (or integer4 single-float double-float) x y))
  (etypecase x
    (integer4
     (isign x y))
    (single-float
     (float-sign y x))
    (double-float
     (float-sign y x))))

(defun dsign (x y)
  (declare (type double-float x y))
  (float-sign y x))

;; Positive difference.  DIM is the generic and specific function for
;; real.  IDIM is for integers; DDIM, doubles.
;;
;; If a1 > a2, returns a1-a2, otherwise 0.  Basically the same as
;; max(0, a1-a2).
(declaim (inline idim dim ddim))
(defun idim (x y)
  (declare (type integer4 x y))
  (max 0 (- x y)))

(defun dim (x y)
  (declare (type (or integer4 single-float double-float) x y))
  (etypecase x
    (integer4
     (max 0 (- x y)))
    (single-float
     (max 0f0 (- x y)))
    (double-float
     (max 0d0 (- x y)))))

(defun ddim (x y)
  (declare (type double-float x y))
  (max 0d0 (- x y)))

;; Double-precision product.  How this is done isn't specified, but I
;; suspect the real args are converted to doubles and then the product
;; is computed.
(defun dprod (x y)
  (declare (single-float x y))
  (* (float x 1d0) (float y 1d0)))

;; The max and min functions.
;;
;; MAX is the generic. MAX0, AMAX1, and DMAX1 returns the max of the
;; args with the same type as the args.
;;
;; AMAX0 takes integer args and returns the max as a real. MAX1 takes
;; real args and returns the max as a integer.  (How the conversion is
;; done isn't specified.)
;;
;; Should we make these macros that expand directly to the appropriate
;; max?
(defun max0 (x y &rest z)
  (declare (integer x y))
  (apply #'max x y z))
(defun amax1 (x y &rest z)
  (declare (single-float x y))
  (apply #'max x y z))
(defun dmax1 (x y &rest z)
  (declare (double-float x y))
  (apply #'max x y z))
(defun max1 (x y &rest z)
  (declare (single-float x y))
  (int (apply #'max x y z)))
(defun amax0 (x y &rest z)
  (declare (integer4 x y))
  (float (apply #'max x y z) 1f0))

(defun min0 (x y &rest z)
  (apply #'min x y z))
(defun amin1 (x y &rest z)
  (apply #'min x y z))
(defun dmin1 (x y &rest z)
  (apply #'min x y z))

(defun amin0 (x y &rest z)
  (float (apply #'min x y z)))
(defun min1 (x y &rest z)
  (nint (apply #'min x y z)))

;; Define some compile macros for these max/min functions.
#+cmu
(progn
(define-compiler-macro max0 (&rest args)
  `(max ,@args))
(define-compiler-macro amax1 (&rest args)
  `(max ,@args))
(define-compiler-macro dmax1 (&rest args)
  `(max ,@args))
(define-compiler-macro min0 (&rest args)
  `(min ,@args))
(define-compiler-macro amin1 (&rest args)
  `(min ,@args))
(define-compiler-macro dmin1 (&rest args)
  `(min ,@args))
(define-compiler-macro min1 (&rest args)
  `(nint (min ,@args)))

(define-compiler-macro amax0 (&rest args)
  `(float (max ,@args)))
(define-compiler-macro max1 (&rest args)
  `(nint (max ,@args)))

(define-compiler-macro amin0 (&rest args)
  `(float (min ,@args)))
(define-compiler-macro min1 (&rest args)
  `(nint (min ,@args)))
) ; end progn

(defun len (s)
  (length s))

(defun index (s1 s2)
  (or (search s1 s2) 0))

;; These string operations need some work!
(defun lge (s1 s2)
  (string>= s1 s2))
(defun lgt (s1 s2)
  (string> s1 s2))
(defun lle (s1 s2)
  (string<= s1 s2))
(defun llt (s1 s2)
  (string< s1 s2))

(defun fstring-/= (s1 s2)
  (not (string= s1 s2)))
(defun fstring-= (s1 s2)
  (string= s1 s2))
(defun fstring-> (s1 s2)
  (string> s1 s2))
(defun fstring->= (s1 s2)
  (string>= s1 s2))
(defun fstring-< (s1 s2)
  (string< s1 s2))
(defun fstring-<= (s1 s2)
  (string<= s1 s2))


;; AIMAG: imaginary part of a complex number
;; CONJG: conjugate of a complex number
(declaim (inline aimag conjg))
(defun aimag (c)
  (imagpart c))
(defun conjg (c)
  (conjugate c))

(declaim (inline fsqrt flog))
(defun fsqrt (x)
  (typecase x
    (single-float
     (sqrt (the (single-float 0f0) x)))
    (double-float
     (sqrt (the (double-float 0d0) x)))
    (t
     (sqrt x))))

(defun flog (x)
  (typecase x
    (single-float
     (log (the (or (single-float (0f0)) (member 0f0)) x)))
    (double-float
     (log (the (or (double-float (0d0)) (member 0d0)) x)))
    (t
     (log x))))
  
;; Tell Lisp that the arguments always have the correct range.  If
;; this is not true, the original Fortran code was broken anyway, so
;; GIGO (garbage in, garbage out).

(declaim (inline dsqrt csqrt alog dlog clog alog10 dlog10))
(defun dsqrt (x)
  (declare (type (double-float 0d0) x))
  (sqrt  x))
(defun csqrt (x)
  (sqrt x))
(defun alog (x)
  (declare (type (or (single-float (0f0)) (member 0f0)) x))
  (log x))
(defun dlog (x)
  (declare (type (or (double-float (0d0)) (member 0d0)) x))
  (log x))
(defun clog (x)
  (log x))
(defun alog10 (x)
  (declare (type (or (single-float (0f0)) (member 0f0)) x))
  (log x 10f0))
(defun dlog10 (x)
  (declare (type (or (double-float (0d0)) (member 0d0)) x))
  (log x 10.0d0))

(declaim (inline log10))
(defun log10 (x)
  (typecase x
    (single-float
     (log (the (or (single-float (0.0f0)) (member 0f0)) x) 10f0))
    (double-float
     (log (the (or (double-float (0.0d0)) (member 0d0)) x) 10d0))
    (t
     (/ (log x)
	(typecase x
	  ((complex double-float)
	   10d0)
	  ((complex single-float)
	   10f0)
	  (t
	   (coerce 10 (type-of (realpart x)))))))))

(declaim (inline dexp cexp))
(defun dexp (x)
  (declare (type double-float x))
  (exp x))
(defun cexp (x)
  (declare (type complex x))
  (exp x))

(declaim (inline dsin csin dcos ccos dtan ctan dasin dacos datan atan2 datan2 dsinh dcosh dtanh))
(defun dsin (x)
  (declare (type double-float x))
  (sin x))
(defun csin (x)
  (declare (type complex x))
  (sin x))

(defun dcos (x)
  (declare (type double-float x))
  (cos x))
(defun ccos (x)
  (declare (type complex x))
  (cos x))

(defun dtan (x)
  (declare (type double-float x))
  (tan x))
(defun ctan (x)
  (declare (type complex x))
  (tan x))

(defun dasin (x)
  (declare (type double-float x))
  (asin x))
(defun dacos (x)
  (declare (type double-float x))
  (acos x))
(defun datan (x)
  (declare (type double-float x))
  (atan x))
(defun atan2 (x y)
  (declare (type double-float x))
  (atan x y))
(defun datan2 (x y)
  (declare (type double-float x y))
  (atan x y))

(defun dsinh (x)
  (declare (type double-float x))
  (sinh x))
(defun dcosh (x)
  (declare (type double-float x))
  (cosh x))
(defun dtanh (x)
  (declare (type double-float x))
  (tanh x))

(declaim (inline ffloat))
(defun ffloat (x)
  (coerce x 'single-float))

#+nil
(defun process-implied-do (ido low-bnds init)
  (let* ((implied-do (remove '|,| ido))
	 (array (first implied-do))
	 (do-var (elt implied-do (1- (position '= implied-do))))
	 (limits (rest (member '= implied-do)))
	 (start (first limits))
	 (end (second limits))
	 (step (if (>= (length limits) 3)
		   (third limits)
		   1)))
    (cond ((atom array)
	   `(do ((,do-var ,start (+ ,do-var ,step)))
	     ((> ,do-var ,end))
	     (declare (integer4 ,do-var))
	     (fset (fref ,array ,(remove '|,| (second implied-do)) ,low-bnds) (pop ,init))))
	  (t
	   `(do ((,do-var ,start (+ ,do-var ,step)))
	     ((> ,do-var ,end))
	     (declare (integer4 ,do-var))
	     ,(process-implied-do (remove '|,| array) low-bnds init))))))

(defun process-implied-do (ido low-bnds var-types init)
  (destructuring-bind (data-vars (index-var start end &optional step))
      ido
    (labels
	((convert-type (type)
	   (if (eq type 'integer4)
	       `(truncate (pop ,init))
	       `(coerce (pop ,init) ',type)))
	 (map-vars (v)
	   (mapcar #'(lambda (x b vt)
		       `(fset (fref ,(first x) ,(second x) ((,b)))
			 ,(convert-type vt)))
		   v low-bnds var-types)))
    `(do ((,index-var ,start (+ ,index-var ,(or step 1))))
         ((> ,index-var ,end))
       ,@(map-vars data-vars))
    )))


;; Process implied do loops for data statements
(defmacro data-implied-do (implied-do low-bnds var-types vals)
  (let ((v (gensym)))
    `(let ((,v ',vals))
      ,(process-implied-do implied-do low-bnds var-types v))))

;-----------------------------------------------------------------------------  ; end of macros.l
   
;; Map Fortran logical unit numbers to Lisp streams

(defparameter *lun-hash*
  (let ((table (make-hash-table)))
    (setf (gethash 6 table) *standard-output*)
    (setf (gethash 5 table) *standard-input*)
    (setf (gethash t table) *standard-output*)
    table))

#+nil
(defun lun->stream (lun)
  (let ((stream (gethash lun *lun-hash*)))
    (if stream
	stream
	(setf (gethash lun *lun-hash*)
	      (open (format nil "fort~d.dat" lun)
		    :direction :output
		    :if-exists :rename)))))

(defun lun->stream (lun &optional readp)
  (let ((stream (gethash lun *lun-hash*)))
    (if stream
	stream
	(cond ((integerp lun)
	       (setf (gethash lun *lun-hash*)
		     (open (format nil "fort~d.dat" lun)
			   :direction :output
			   :if-exists :rename)))
	      ((stringp lun)
	       (setf (gethash lun *lun-hash*)
		     (if readp
			 (make-string-input-stream lun)
			 (make-string-output-stream))))
	      ))))

(defun init-fortran-io ()
  "Initialize the F2CL Fortran I/O subsystem to sensible defaults"
  (clrhash *lun-hash*)
  (setf (gethash 6 *lun-hash*) *standard-output*)
  (setf (gethash 5 *lun-hash*) *standard-input*)
  (setf (gethash t *lun-hash*) *standard-output*))

(defun close-fortran-io ()
  "Close all F2CL Fortran units (except for standard output and input)
causing all pending operations to be flushed"
  (maphash #'(lambda (key val)
	       (when (and (streamp val) (not (member key '(5 6 t))))
		 (format t "Closing unit ~A: ~A~%" key val)
		 (close val)))
	       *lun-hash*))

(declaim (ftype (function (t) stream) lun->stream))

(defmacro fformat (dest-lun format-cilist &rest args)
  (let ((stream (gensym)))
    `(let ((,stream (lun->stream ,dest-lun)))
      (execute-format-main ,stream ',format-cilist ,@args)
      (when (stringp ,dest-lun)
	(replace ,dest-lun (get-output-stream-string ,stream))))))

(defun execute-format (top stream format arg-list)
  (do ((formats format (if (and top (null formats))
			   format
			   (rest formats))))
      ((or (null arg-list)
	   (and (not top)
		(null formats)))
       ;;(format t "~&formats = ~S~%" formats)
       (do ((more formats (rest more)))
	   ((not (stringp (first more))))
	 (format stream (first more)))
       arg-list)
    (when (null formats)
      (setf formats format))
    #+nil
    (let ((*print-circle* t))
      (format t "~&formats = ~S~%" formats))
    (cond ((listp (first formats))
	   (format stream (caar formats) (pop arg-list)))
	  ((numberp (first formats))
	   ;; Repeat a group some fixed number of times
	   (dotimes (k (first formats))
	     ;;(format t "k = ~A, format = ~S~%" k (second formats))
	     (setf arg-list
		   (execute-format nil stream (second formats) arg-list)))
	   (setf formats (rest formats))
	   ;;(format t "  cont with format = ~S~%" formats)
	   )
	   ((eq (first formats) t)
	    ;; Repeat "forever" (until we run out of data)
	    (loop while arg-list do
		  (setf arg-list
			(execute-format nil stream (second formats) arg-list))
		  ;; Output a newline after the repeat (I think Fortran says this)
		  (format stream "~%")))
	  (t
	   (format stream (car formats))))))
	   
       
(defun execute-format-main (stream format &rest args)
  (let ((format-list (copy-tree format))
	(arg-list (apply #'append (map 'list #'(lambda (x)
						 (cond ((numberp x)
							(list x))
						       ((stringp x)
							(list x))
						       (t
							(coerce x 'list))))
				       args))))
    (execute-format t stream format-list arg-list)))


#||
(defmacro fformat1 (dest directive arg)
  (let ((val (gensym)))
    `(let ((,val ,arg))
      (cond ((and (arrayp ,val)
		  (not (stringp ,val)))
	     (dotimes (k (array-total-size ,val))
	       (format ,dest ,directive (row-major-aref ,val k))
	       (terpri ,dest)))
	    ((listp ,val)
	     (dolist (item ,val)
	       (format ,dest ,directive item)
	       (terpri ,dest)))
	    (t
	     (format ,dest ,directive ,val))))))

(defun expand-format (dest cilist args)
  (if (equal cilist '("~A~%"))
      (append (mapcar #'(lambda (arg) `(fformat1 ,dest "~A " ,arg)) args)
	   `((format ,dest "~%")))

      ;loop through directives, consume arguments
      (do ((res '())
	   (directives cilist (cdr directives))
	   (arglist args arglist))
	  ((null directives)
	   (nreverse res))
	(cond ((stringp (first directives))
	       ;;(format t "~a~%" (first directives))
	       (push `(format ,dest ,(first directives))
		     res))
	      (t
	       (push `(fformat1 ,dest
		       ,(car (first directives)) 
		       ,(first arglist))
		     res)
	       (setq arglist (cdr arglist)))))))
||#

;; Initialize a multi-dimensional array of character strings. I think
;; we need to do it this way to appease some picky compilers (like
;; CMUCL).  The initial-element is needed to get rid of a warning
;; about the default initial element not being a simple
;; string. However, this initializes all elements of the array to
;; exactly the same string, so we loop over the entire array contents
;; and initialize each element with a string of the appropriate
;; length.  The string is initialized with #\Space because it seems
;; that's what Fortran initializes it to.
(defmacro f2cl-init-string (dims len)
  (let ((init (gensym))
	(new-dims (if (every #'numberp dims)
		      `',dims
		      `(list ,@dims))))
    `(let ((,init (make-array ,new-dims
			      :element-type `(simple-array base-char (,',@len))
			      :initial-element (make-string ,@len))))
       (dotimes (k (array-total-size ,init))
	 (setf (row-major-aref ,init k)
	       (make-string ,@len :initial-element #\Space)))
       ,init)))

;; This macro is supposed to set LHS to the RHS assuming that the LHS
;; is a Fortran CHARACTER type of length LEN.
;;
;; Currently, converts the RHS to the appropriate length string and
;; assigns it to the LHS.  However, this can generate quite a bit of
;; garbage.  We might want to be a bit smarter and use loops to
;; replace the individual characters of the LHS with the appropriate
;; characters from the RHS.
(defmacro f2cl-set-string (lhs rhs (string len))
  (declare (ignore string))
  (etypecase lhs
    (symbol
     ;; Assignment to a simple string.
     `(setf ,lhs (f2cl-string ,rhs ,len)))
    (list
     ;; Assignment to an array
     `(fset ,lhs (f2cl-string ,rhs ,len)))))

(defun f2cl-string (string len)
  ;; Create a string of the desired length by either appending spaces
  ;; or truncating the string.
  (let ((slen (length string)))
    (cond ((= slen len)
	   ;; Need to make a copy of the string, so we don't have
	   ;; duplicated structure.
	   (copy-seq string))
	  ((> slen len)
	   ;; Truncate the string
	   (subseq string 0 len))
	  (t
	   ;; String is too short, so append some spaces
	   (concatenate 'string string (make-string (- len slen) :initial-element #\Space))))))


;;; Strictly speaking, this is not part of Fortran, but so many
;;; Fortran packages use these routines, we're going to add them here.
;;; They're much easier to implement in Lisp than in Fortran!

;;
;;  DOUBLE-PRECISION MACHINE CONSTANTS
;;  D1MACH( 1) = B**(EMIN-1), THE SMALLEST POSITIVE MAGNITUDE.
;;  D1MACH( 2) = B**EMAX*(1 - B**(-T)), THE LARGEST MAGNITUDE.
;;  D1MACH( 3) = B**(-T), THE SMALLEST RELATIVE SPACING.
;;  D1MACH( 4) = B**(1-T), THE LARGEST RELATIVE SPACING.
;;  D1MACH( 5) = LOG10(B)
;;
(defun d1mach (i)
  (ecase i
    (1 least-positive-normalized-double-float)
    (2 most-positive-double-float)
    (3 double-float-epsilon)
    (4 (scale-float double-float-epsilon 1))
    (5 (log (float-radix 1d0) 10d0))))

(defun r1mach (i)
  (ecase i
    (1 least-positive-normalized-single-float)
    (2 most-positive-single-float)
    (3 single-float-epsilon)
    (4 (scale-float single-float-epsilon 1))
    (5 (log (float-radix 1d0) 10d0))))

;;
;;     This is the CMLIB version of I1MACH, the integer machine
;;     constants subroutine originally developed for the PORT library.
;;
;;     I1MACH can be used to obtain machine-dependent parameters
;;     for the local machine environment.  It is a function
;;     subroutine with one (input) argument, and can be called
;;     as follows, for example
;;
;;          K = I1MACH(I)
;;
;;     where I=1,...,16.  The (output) value of K above is
;;     determined by the (input) value of I.  The results for
;;     various values of I are discussed below.
;;
;;  I/O unit numbers.
;;    I1MACH( 1) = the standard input unit.
;;    I1MACH( 2) = the standard output unit.
;;    I1MACH( 3) = the standard punch unit.
;;    I1MACH( 4) = the standard error message unit.
;;
;;  Words.
;;    I1MACH( 5) = the number of bits per integer storage unit.
;;    I1MACH( 6) = the number of characters per integer storage unit.
;;
;;  Integers.
;;    assume integers are represented in the S-digit, base-A form
;;
;;               sign ( X(S-1)*A**(S-1) + ... + X(1)*A + X(0) )
;;
;;               where 0 .LE. X(I) .LT. A for I=0,...,S-1.
;;    I1MACH( 7) = A, the base.
;;    I1MACH( 8) = S, the number of base-A digits.
;;    I1MACH( 9) = A**S - 1, the largest magnitude.
;;
;;  Floating-Point Numbers.
;;    Assume floating-point numbers are represented in the T-digit,
;;    base-B form
;;               sign (B**E)*( (X(1)/B) + ... + (X(T)/B**T) )
;;
;;               where 0 .LE. X(I) .LT. B for I=1,...,T,
;;               0 .LT. X(1), and EMIN .LE. E .LE. EMAX.
;;    I1MACH(10) = B, the base.
;;
;;  Single-Precision
;;    I1MACH(11) = T, the number of base-B digits.
;;    I1MACH(12) = EMIN, the smallest exponent E.
;;    I1MACH(13) = EMAX, the largest exponent E.
;;
;;  Double-Precision
;;    I1MACH(14) = T, the number of base-B digits.
;;    I1MACH(15) = EMIN, the smallest exponent E.
;;    I1MACH(16) = EMAX, the largest exponent E.
(defun i1mach (i)
  (ecase i
    ;; What does the unit numbers really mean in Lisp?  What do we
    ;; really want?
    
    ;; The standard input unit
    (1 5)
    ;; The standard output unit
    (2 6)
    ;; The standard punch unit
    (3 6)
    ;; The standard error message unit
    (4 6)

    ;; The number of bits per integer storage unit.  What does this
    ;; mean in Lisp?
    (5
     (integer-length most-positive-fixnum))
    ;; The number of characters per integer storage unit.  What does
    ;; this mean in Lisp?
    (6 4)

    ;; The base of integers.  Assume 2's complement
    (7 2)
    ;; The number of base-2 digits.  Assume fixnum size?
    (8 (integer-length most-positive-fixnum))
    ;; The largest magnitude
    (9 most-positive-fixnum)

    ;; Base of floating-poing representation
    (10 (float-radix 1f0))
    ;; Number of digits in representation
    (11 (float-digits 1f0))
    ;; Smallest exponent
    (12 (multiple-value-bind (frac exp sign)
	    (decode-float least-positive-normalized-single-float)
	  (declare (ignore frac sign))
	  (+ exp 1)))
    ;; Largest exponent
    (13 (multiple-value-bind (frac exp sign)
	    (decode-float most-positive-single-float)
	  (declare (ignore frac sign))
	  (- exp 1)))
    ;; Same for double-precision
    (14 (float-digits 1d0))
    (15 (multiple-value-bind (frac exp sign)
	    (decode-float least-positive-normalized-double-float)
	  (declare (ignore frac sign))
	  (+ exp 1)))
    (16 (multiple-value-bind (frac exp sign)
	    (decode-float most-positive-double-float)
	  (declare (ignore frac sign))
	  (- exp 1)))
    ))
     

;;;-------------------------------------------------------------------------
;;; end of macros.l
;;;
;;; $Id: f2cl-lib.lisp,v 1.1 2002-04-26 13:03:40 rtoy Exp $
;;; $Log: f2cl-lib.lisp,v $
;;; Revision 1.1  2002-04-26 13:03:40  rtoy
;;; Initial revision.
;;;
;;; Revision 1.46  2002/03/19 02:23:09  rtoy
;;; According to the rules of Fortran, the initializers in a DATA
;;; statement are supposed to be converted to match the type of the
;;; variable that is being initialized.  Make it so by passing the
;;; variable type to the macro DATA-IMPLIED-DO so that the conversion can
;;; be done.
;;;
;;; Revision 1.45  2002/03/18 23:34:16  rtoy
;;; Was not correctly handling some implied do loops containing multiple
;;; variables in the loop in data statements.  Fix that and clean up some
;;; of the processing.  (Should probably do this kind of work in the f2cl
;;; compiler instead of at runtime, but it's only done once at runtime, so
;;; it's not a big deal.)
;;;
;;; Revision 1.44  2002/03/11 16:44:00  rtoy
;;; o Remove an extra paren.
;;; o Indent FIND-ARRAY-DATA better.
;;; o Declare the iteration count to be of type INTEGER4.
;;; o Added macros INT-ADD, INT-SUB, INT-MUL to tell the compiler that the
;;;   integer operation can't overflow.  (First try.)
;;; o Tell the compiler that the result of truncate is an INTEGER4 in INT.
;;;
;;; Revision 1.43  2002/03/06 23:07:19  rtoy
;;; o Make INT return an integer4 type, not integer.
;;; o log10 was thinking it could generate complex result, but that's not
;;;   true.  Declare the arg correctly so the compiler knows it can't.
;;;
;;; Revision 1.42  2002/03/06 03:21:16  rtoy
;;; o Speed up FIND-ARRAY-DATA a little by declaring the offset to be a
;;;   fixnum, which it has to be since it's an index to an array.
;;; o Remove the truncate/ftruncate-towards-zero functions.
;;; o For INT, AINT, and friends, TRUNCATE and FTRUNCATE are the right
;;;   functions we want to use.  (Stupid me!)
;;; o Update/correct some random comments.
;;;
;;; Revision 1.41  2002/02/17 15:55:29  rtoy
;;; o For all array accessors, wrap the offset calculations with (the
;;;   fixnum ...) since they have to be anyway.  Speeds up calculations
;;;   quite a bit.
;;; o FREF takes an additional optional OFFSET arg to specify an offset
;;;   for the new array slicing method.
;;; o Added WITH-ARRAY-DATA and FIND-ARRAY-DATA to support the new
;;;   array-slicing method.
;;; o For FDO, add (the integer4 ...) for loop index calculations.
;;; o Add some more assertions for ISIGN and LOG10 to help the compiler
;;;   generate better code.
;;;
;;; Revision 1.40  2002/02/10 03:43:51  rtoy
;;; Partial support for WRITE statements writing to a string instead of
;;; logical unit.
;;;
;;; Revision 1.39  2002/02/09 15:59:26  rtoy
;;; o Add more and better comments
;;; o AINT was broken because it should accept any range of floats.
;;; o DIM and friends computed the wrong thing!
;;; o Change DPROD to convert to doubles first.
;;; o Some cleanup of MAX and MIN
;;;
;;; Revision 1.38  2002/02/08 23:38:36  rtoy
;;; Use ARRAY-TOTAL-SIZE to compute how many elements are in the slice
;;; instead of the f2cl declared/derived bounds so that we can dynamically
;;; change the size of the array.  Useful for an array in a common block.
;;;
;;; Revision 1.37  2002/02/07 03:23:15  rtoy
;;; Add functions to initialize F2CL's Fortran I/O and to close all of
;;; F2CL's open units.
;;;
;;; Revision 1.36  2002/02/04 03:23:46  rtoy
;;; o Make *lun-hash* a defparameter instead of a defvar.
;;; o Fix up i1mach so that the unit numbers match *lun-hash*.
;;;
;;; Revision 1.35  2002/01/13 16:29:00  rtoy
;;; o This file is in the f2cl-lib package now
;;; o Deleted some unused code.
;;; o Moved *INTRINSIC-FUNCTION-NAMES* to f2cl1.l
;;;
;;; Revision 1.34  2002/01/06 23:11:04  rtoy
;;; o Rename *intrinsic_function_names* to use dashes.
;;; o Comment out some unused functions and macros.
;;;
;;; Revision 1.33  2001/04/30 15:38:12  rtoy
;;; Add a version of I1MACH.
;;;
;;; Revision 1.32  2001/04/26 17:49:19  rtoy
;;; o SIGN and DIM are Fortran generic instrinsics.  Make it so.
;;; o Added D1MACH and R1MACH because they're very common in Fortran
;;;   libraries.
;;;
;;; Revision 1.31  2001/02/26 15:38:23  rtoy
;;; Move *check-array-bounds* from f2cl1.l to macros.l since the generated
;;; code refers to it.  Export this variable too.
;;;
;;; Revision 1.30  2000/08/30 17:00:42  rtoy
;;; o In EXECUTE-FORMAT, handle the case where the group is supposed to be
;;;   repeated "forever" (as indicated by a repetition factor of T).
;;; o Remove some more unused code.
;;;
;;; Revision 1.29  2000/08/27 16:36:07  rtoy
;;; Clean up handling of format statements.  Should handle many more
;;; formats correctly now.
;;;
;;; Revision 1.28  2000/08/07 19:00:47  rtoy
;;; Add type ARRAY-STRINGS to denote an array of strings.
;;;
;;; Revision 1.27  2000/08/03 13:45:53  rtoy
;;; Make FFORMAT1 handle lists that we get from implied do loops.
;;;
;;; The whole FFORMAT stuff needs to be rethought if we really want to
;;; support Fortran output.
;;;
;;; Revision 1.26  2000/08/01 22:10:41  rtoy
;;; o Try to make the Fortran functions to convert to integers work the
;;;   way Fortran says they should.
;;; o Declaim most of the intrinsics as inline so we don't have an
;;;   additional function call for simple things.
;;; o Add some compiler macros for Fortran max/min functions to call the
;;;   Lisp max/min functions withouth using #'apply.
;;; o Try to declare the args to functions with branchs appropriately,
;;;   even in the face of signed zeroes.
;;;
;;; Revision 1.25  2000/07/28 22:10:05  rtoy
;;; Remove unused var from ARRAY-SLICE.
;;;
;;; Revision 1.24  2000/07/28 17:09:13  rtoy
;;; o We are in the f2cl package now.
;;; o Remove the export expression.
;;; o // is now called F2CL-//, to prevent problems with the lisp variable
;;;   //.
;;; o REAL is now called FREAL, to prevent problems with the lisp type
;;;   REAL.
;;;
;;; Revision 1.23  2000/07/27 16:39:17  rtoy
;;; We want to be in the CL-USER package, not the USER package.
;;;
;;; Revision 1.22  2000/07/20 13:44:38  rtoy
;;; o Remove old fref macro
;;; o Add some comments
;;; o Add macro ARRAY-INITIALIZE to handle creating the appropriate for to
;;;   give to make-array :initial-contents.
;;;
;;; Revision 1.21  2000/07/19 13:54:27  rtoy
;;; o Add the types ARRAY-DOUBLE-FLOAT, ARRAY-SINGLE-FLOAT, and
;;;   ARRAY-INTEGER4.
;;; o All arrays are 1-D now to support slicing of Fortran arrays
;;;   correctly.
;;; o All arrays are in column-major order just like Fortran (and the
;;;   opposite of Lisp).  This is to support slicing of arrays.  Modified
;;;   FREF to support this by taking an extra arg for the dimensions of
;;;   the array.
;;; o Added macro ARRAY-SLICE to slice the array properly.
;;; o Optimized routine DMIN1 a bit.   (Need to do that for more routines.)
;;;
;;; Revision 1.20  2000/07/14 15:50:59  rtoy
;;; Get rid of *dummy_var*.  It's not used anymore.
;;;
;;; Revision 1.19  2000/07/13 16:55:34  rtoy
;;; To satisfy the Copyright statement, we have placed the RCS logs in
;;; each source file in f2cl.  (Hope this satisfies the copyright.)
;;;
;;;-----------------------------------------------------------------------------
