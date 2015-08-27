#lang racket
(require pict rackunit
         (for-syntax syntax/parse)
         racket/draw racket/class)

(define (->bitmap p)
  (define b (pict->bitmap p))
  (define w (send b get-width))
  (define h (send b get-height))

   (define its (make-bytes
                (*
                 w h
                 4)
                255))
   (send b get-argb-pixels
         0 0
         (send b get-width)
         (send b get-height)
         its)
   (define mask (send b get-loaded-mask))
   (when mask
     (send b get-argb-pixels 0 0 w h its #t))
  its)

(define-check (check-pict=?/msg actual expected msg)
  (unless (equal? (->bitmap actual) (->bitmap expected))
    (fail-check msg)))
(define-syntax-rule (check-pict=? actual expected)
  (check-pict=?/msg actual expected ""))

(define-syntax (gen-case stx)
  (syntax-parse stx
    [(_ e:expr [(n) (m:id b:expr ...)] ...)
     (with-syntax ([((i ...) ...) (map generate-temporaries (syntax->list #'((b ...) ...)))])
       #`(case e
           [(n)
            (define i (call-with-values (lambda () b) list)) ...
            (values
             `(m ,(first i) ...)
             (m (if (null? (rest i)) (first i) (second i)) ...))]
           ...))]))

(define (generate-pict)
  (define-values (l p)
  (let loop ([depth 0])
    (define (gen) (loop (add1 depth)))
    (gen-case
     (if (> depth 4) (random 3) (random 11))
     [(0) (text "sefsefse")]
     [(1) (rectangle (random 10) (random 10))]
     [(2) (arrow (random 10) (random 10))]
     [(3) (frame (gen))]
     [(4) (cc-superimpose (gen) (gen))]
     [(5) (vl-append (gen) (gen))]
     [(6) (hbl-append (gen) (gen))]
     [(7) (rb-superimpose (gen) (gen))]
     [(8) (panorama (gen))]
     [(9) (scale (gen) (random))]
     [(10) (inset (gen) (random 10) (random 10) (random 10) (random 10))])))
  (values l (cc-superimpose (blank 200) p)))

(test-case
 "freeze random testing"
 (for ([i 1000])
   (define-values (l p) (generate-pict))
   (check-pict=?/msg p (freeze p) (format "~a" l))))

(test-case
 "scale-to-fit"
 (define p (rectangle 10 20))
 (check-pict=? (scale-to-fit p p) p)
 (check-pict=? (scale-to-fit p (scale p 2)) (scale p 2))
 (check-pict=? (scale-to-fit p 40 40) (scale p 2))
 (check-pict=? (scale-to-fit p 40 40 #:mode 'inset)
               (cc-superimpose (blank 40 40)
                               (scale p 2)))
 (check-pict=? (scale-to-fit p 40 40 #:mode 'distort) (scale p 4 2)))


;; check whether the new implementation of shapes (with borders and colors)
;; are equivalent to the old ones (for the feature subset of the old one)

(define (old-filled-rectangle w h #:draw-border? [draw-border? #t])
  (dc
   (lambda (dc x y)
     (let ([b (send dc get-brush)]
           [p (send dc get-pen)])
       (send dc set-brush (send the-brush-list find-or-create-brush
                                (send p get-color)
                                'solid))
       (unless draw-border?
         (send dc set-pen "black" 1 'transparent))
       (send dc draw-rectangle x y w h)
       (send dc set-brush b)
       (send dc set-pen p)))
   w
   h))

(define (old-rectangle w h)
  (dc
   (lambda (dc x y)
     (let ([b (send dc get-brush)])
       (send dc set-brush (send the-brush-list find-or-create-brush
                                "white" 'transparent))
       (send dc draw-rectangle x y w h)
       (send dc set-brush b)))
   w
   h))

(define (old-rounded-rectangle w h [corner-radius -0.25] #:angle [angle 0])
  (let ([dc-path (new dc-path%)])
    (send dc-path rounded-rectangle 0 0 w h corner-radius)
    (send dc-path rotate angle)
    (let-values ([(x y w h) (send dc-path get-bounding-box)])
      (dc (λ (dc dx dy)
            (let ([brush (send dc get-brush)])
              (send dc set-brush (send the-brush-list find-or-create-brush
                                       "white" 'transparent))
              (send dc draw-path dc-path (- dx x) (- dy y))
              (send dc set-brush brush)))
          w
          h))))

(define (old-filled-rounded-rectangle w h [corner-radius -0.25] #:angle [angle 0] #:draw-border? [draw-border? #t])
  (let ([dc-path (new dc-path%)])
    (send dc-path rounded-rectangle 0 0 w h corner-radius)
    (send dc-path rotate angle)
    (let-values ([(x y w h) (send dc-path get-bounding-box)])
      (dc (λ (dc dx dy) 
            (let ([brush (send dc get-brush)]
                  [pen (send dc get-pen)])
              (send dc set-brush (send the-brush-list find-or-create-brush
                                       (send (send dc get-pen) get-color)
                                       'solid))
              (unless draw-border?
                (send dc set-pen "black" 1 'transparent))
              (send dc draw-path dc-path (- dx x) (- dy y))
              (send dc set-brush brush)
              (send dc set-pen pen)))
          w
          h))))

(define (old-circle size) (ellipse size size))

(define (old-ellipse width height)
  (dc (lambda (dc x y)
        (let ([b (send dc get-brush)])
          (send dc set-brush (send the-brush-list find-or-create-brush
                                   "white" 'transparent))
          (send dc draw-ellipse x y width height)
          (send dc set-brush b)))
      width height))

(define (old-disk size #:draw-border? [draw-border? #t])
  (filled-ellipse size size #:draw-border? draw-border?))

(define (old-filled-ellipse width height #:draw-border? [draw-border? #t])
  (dc (lambda (dc x y)
        (define b (send dc get-brush))
        (define p (send dc get-pen))
        (send dc set-brush (send the-brush-list find-or-create-brush
                                 (send (send dc get-pen) get-color)
                                 'solid))
        (unless draw-border?
          (send dc set-pen "black" 1 'transparent))
        (send dc draw-ellipse x y width height)
        (send dc set-brush b)
        (send dc set-pen p))
      width height))

(define (random-boolean) (> (random) 0.5))
(define (generate-shapes depth)
  (define r (random (if (= depth 0) 8 15)))
  (case r
    [(0) (let ([w (random 10)]
               [h (random 10)])
           (values (old-rectangle w h)
                   (rectangle w h)
                   `(rectangle ,w ,h)))]
    [(1) (let ([w (random 10)]
               [h (random 10)]
               [border? (random-boolean)])
           (values (old-filled-rectangle w h #:draw-border? border?)
                   (filled-rectangle w h #:draw-border? border?)
                   `(filled-rectangle ,w ,h #:draw-border? ,border?)))]
    [(2) (let ([w (random 10)]
               [h (random 10)]
               [corner (- (random) 0.5)]
               [angle (* (- (random) 0.5) 2 pi)])
           (values (old-rounded-rectangle w h corner #:angle angle)
                   (rounded-rectangle w h corner #:angle angle)
                   `(rounded-rectangle ,w ,h ,corner #:angle ,angle)))]
    [(3) (let ([w (random 10)]
               [h (random 10)]
               [border? (random-boolean)]
               [corner (- (random) 0.5)]
               [angle (* (- (random) 0.5) 2 pi)])
           (values (old-filled-rounded-rectangle w h corner
                                                 #:angle angle
                                                 #:draw-border? border?)
                   (filled-rounded-rectangle w h corner
                                             #:angle angle
                                             #:draw-border? border?)
                   `(filled-rounded-rectangle ,w ,h ,corner
                                              #:angle ,angle
                                              #:draw-border? ,border?)))]
    [(4) (let ([r (random 10)])
           (values (old-circle r)
                   (circle r)
                   `(circle ,r)))]
    [(5) (let ([w (random 10)]
               [h (random 10)])
           (values (old-ellipse w h)
                   (ellipse w h)
                   `(ellipse ,w ,h)))]
    [(6) (let ([r (random 10)]
               [border? (random-boolean)])
           (values (old-disk r #:draw-border? border?)
                   (disk r #:draw-border? border?)
                   `(disk ,r #:draw-border? ,border?)))]
    [(7) (let ([w (random 10)]
               [h (random 10)]
               [border? (random-boolean)])
           (values (old-filled-ellipse w h #:draw-border? border?)
                   (filled-ellipse w h #:draw-border? border?)
                   `(filled-ellipse ,w ,h #:draw-border? ,border?)))]
    [(8) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                      [(old2 new2 t2) (generate-shapes (sub1 depth))])
           (values (cc-superimpose old1 old2)
                   (cc-superimpose new1 new2)
                   `(cc-superimpose ,t1 ,t2)))]
    [(9) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                      [(old2 new2 t2) (generate-shapes (sub1 depth))])
           (values (ht-append old1 old2)
                   (ht-append new1 new2)
                   `(ht-append ,t1 ,t2)))]
    [(10) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                       [(old2 new2 t2) (generate-shapes (sub1 depth))])
            (values (hc-append old1 old2)
                    (hc-append new1 new2)
                    `(hc-append ,t1 ,t2)))]
    [(11) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                       [(old2 new2 t2) (generate-shapes (sub1 depth))])
            (values (hb-append old1 old2)
                    (hb-append new1 new2)
                    `(hb-append ,t1 ,t2)))]
    [(12) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                       [(old2 new2 t2) (generate-shapes (sub1 depth))])
            (values (vl-append old1 old2)
                    (vl-append new1 new2)
                    `(vl-append ,t1 ,t2)))]
    [(13) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                       [(old2 new2 t2) (generate-shapes (sub1 depth))])
            (values (vc-append old1 old2)
                    (vc-append new1 new2)
                    `(vc-append ,t1 ,t2)))]
    [(14) (let-values ([(old1 new1 t1) (generate-shapes (sub1 depth))]
                       [(old2 new2 t2) (generate-shapes (sub1 depth))])
            (values (vr-append old1 old2)
                    (vr-append new1 new2)
                    `(vr-append t1 t2)))]))

(test-case
 "old and new shapes"
 (for ([i 1000])
   (define-values (old new trace) (generate-shapes 4))
   (check-pict=?/msg old new (format "~a" trace))))