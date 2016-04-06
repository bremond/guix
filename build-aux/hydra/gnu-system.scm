;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2012, 2013, 2014, 2015, 2016 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

;;;
;;; This file defines build jobs for the Hydra continuation integration
;;; tool.
;;;

;; Attempt to use our very own Guix modules.
(eval-when (compile load eval)

  ;; Ignore any available .go, and force recompilation.  This is because our
  ;; checkout in the store has mtime set to the epoch, and thus .go files look
  ;; newer, even though they may not correspond.
  (set! %fresh-auto-compile #t)

  (and=> (assoc-ref (current-source-location) 'filename)
         (lambda (file)
           (let ((dir (string-append (dirname file) "/../..")))
             (format (current-error-port) "prepending ~s to the load path~%"
                     dir)
             (set! %load-path (cons dir %load-path))))))

(use-modules (guix config)
             (guix store)
             (guix grafts)
             (guix packages)
             (guix derivations)
             (guix monads)
             ((guix licenses) #:select (gpl3+))
             ((guix utils) #:select (%current-system))
             ((guix scripts system) #:select (read-operating-system))
             (gnu packages)
             (gnu packages gcc)
             (gnu packages base)
             (gnu packages gawk)
             (gnu packages guile)
             (gnu packages gettext)
             (gnu packages compression)
             (gnu packages multiprecision)
             (gnu packages make-bootstrap)
             (gnu packages commencement)
             (gnu packages package-management)
             (gnu system)
             (gnu system vm)
             (gnu system install)
             (srfi srfi-1)
             (srfi srfi-26)
             (ice-9 match))

;; XXX: Debugging hack: since `hydra-eval-guile-jobs' redirects the output
;; port to the bit bucket, let us write to the error port instead.
(setvbuf (current-error-port) _IOLBF)
(set-current-output-port (current-error-port))

(define* (package->alist store package system
                         #:optional (package-derivation package-derivation))
  "Convert PACKAGE to an alist suitable for Hydra."
  `((derivation . ,(derivation-file-name
                    (package-derivation store package system
                                        #:graft? #f)))
    (description . ,(package-synopsis package))
    (long-description . ,(package-description package))
    (license . ,(package-license package))
    (home-page . ,(package-home-page package))
    (maintainers . ("bug-guix@gnu.org"))
    (max-silent-time . ,(or (assoc-ref (package-properties package)
                                       'max-silent-time)
                            3600))                ; 1 hour by default
    (timeout . ,(or (assoc-ref (package-properties package) 'timeout)
                    72000)))) ; 20 hours by default

(define (package-job store job-name package system)
  "Return a job called JOB-NAME that builds PACKAGE on SYSTEM."
  (let ((job-name (symbol-append job-name (string->symbol ".")
                                 (string->symbol system))))
    `(,job-name . ,(cut package->alist store package system))))

(define (package-cross-job store job-name package target system)
  "Return a job called TARGET.JOB-NAME that cross-builds PACKAGE for TARGET on
SYSTEM."
  `(,(symbol-append (string->symbol target) (string->symbol ".") job-name
                    (string->symbol ".") (string->symbol system)) .
    ,(cute package->alist store package system
           (lambda* (store package system #:key graft?)
             (package-cross-derivation store package target system
                                       #:graft? graft?)))))

(define %core-packages
  ;; Note: Don't put the '-final' package variants because (1) that's
  ;; implicit, and (2) they cannot be cross-built (due to the explicit input
  ;; chain.)
  (list gcc-4.8 gcc-4.9 gcc-5 glibc binutils
        gmp mpfr mpc coreutils findutils diffutils patch sed grep
        gawk gnu-gettext hello guile-2.0 zlib gzip xz
        %bootstrap-binaries-tarball
        %binutils-bootstrap-tarball
        %glibc-bootstrap-tarball
        %gcc-bootstrap-tarball
        %guile-bootstrap-tarball
        %bootstrap-tarballs))

(define %packages-to-cross-build
  %core-packages)

(define %cross-targets
  '("mips64el-linux-gnu"
    "mips64el-linux-gnuabi64"))

(define (demo-os)
  "Return the \"demo\" 'operating-system' structure."
  (let* ((dir  (dirname (assoc-ref (current-source-location) 'filename)))
         (file (string-append dir "/demo-os.scm")))
    (read-operating-system file)))

(define (qemu-jobs store system)
  "Return a list of jobs that build QEMU images for SYSTEM."
  (define (->alist drv)
    `((derivation . ,(derivation-file-name drv))
      (description . "Stand-alone QEMU image of the GNU system")
      (long-description . "This is a demo stand-alone QEMU image of the GNU
system.")
      (license . ,gpl3+)
      (home-page . ,%guix-home-page-url)
      (maintainers . ("bug-guix@gnu.org"))))

  (define (->job name drv)
    (let ((name (symbol-append name (string->symbol ".")
                               (string->symbol system))))
      `(,name . ,(cut ->alist drv))))

  (define MiB
    (expt 2 20))

  (if (member system '("x86_64-linux" "i686-linux"))
      (list (->job 'qemu-image
                   (run-with-store store
                     (mbegin %store-monad
                       (set-guile-for-build (default-guile))
                       (system-qemu-image (demo-os)
                                          #:disk-image-size
                                          (* 1400 MiB))))) ; 1.4 GiB
            (->job 'usb-image
                   (run-with-store store
                     (mbegin %store-monad
                       (set-guile-for-build (default-guile))
                       (system-disk-image installation-os
                                          #:disk-image-size
                                          (* 1024 MiB))))))
      '()))

(define (tarball-jobs store system)
  "Return Hydra jobs to build the self-contained Guix binary tarball."
  (define (->alist drv)
    `((derivation . ,(derivation-file-name drv))
      (description . "Stand-alone binary Guix tarball")
      (long-description . "This is a tarball containing binaries of Guix and
all its dependencies, and ready to be installed on non-GuixSD distributions.")
      (license . ,gpl3+)
      (home-page . ,%guix-home-page-url)
      (maintainers . ("bug-guix@gnu.org"))))

  (define (->job name drv)
    (let ((name (symbol-append name (string->symbol ".")
                               (string->symbol system))))
      `(,name . ,(cut ->alist drv))))

  ;; XXX: Add a job for the stable Guix?
  (list (->job 'binary-tarball
               (run-with-store store
                 (mbegin %store-monad
                   (set-guile-for-build (default-guile))
                   (self-contained-tarball))
                 #:system system))))

(define job-name
  ;; Return the name of a package's job.
  (compose string->symbol package-full-name))

(define package->job
  (let ((base-packages
         (delete-duplicates
          (append-map (match-lambda
                       ((_ package _ ...)
                        (match (package-transitive-inputs package)
                          (((_ inputs _ ...) ...)
                           inputs))))
                      %final-inputs))))
    (lambda (store package system)
      "Return a job for PACKAGE on SYSTEM, or #f if this combination is not
valid."
      (cond ((member package base-packages)
             #f)
            ((supported-package? package system)
             (package-job store (job-name package) package system))
            (else
             #f)))))


;;;
;;; Hydra entry point.
;;;

(define (hydra-jobs store arguments)
  "Return Hydra jobs."
  (define subset
    (match (assoc-ref arguments 'subset)
      ("core" 'core)                              ; only build core packages
      (_ 'all)))                                  ; build everything

  (define (cross-jobs system)
    (define (from-32-to-64? target)
      ;; Return true if SYSTEM is 32-bit and TARGET is 64-bit.  This hack
      ;; prevents known-to-fail cross-builds from i686-linux or armhf-linux to
      ;; mips64el-linux-gnuabi64.
      (and (or (string-prefix? "i686-" system)
               (string-prefix? "armhf-" system))
           (string-suffix? "64" target)))

    (define (same? target)
      ;; Return true if SYSTEM and TARGET are the same thing.  This is so we
      ;; don't try to cross-compile to 'mips64el-linux-gnu' from
      ;; 'mips64el-linux'.
      (string-contains target system))

    (define (either proc1 proc2)
      (lambda (x)
        (or (proc1 x) (proc2 x))))

    (append-map (lambda (target)
                  (map (lambda (package)
                         (package-cross-job store (job-name package)
                                            package target system))
                       %packages-to-cross-build))
                (remove (either from-32-to-64? same?) %cross-targets)))

  ;; Turn off grafts.  Grafting is meant to happen on the user's machines.
  (parameterize ((%graft? #f))
    ;; Return one job for each package, except bootstrap packages.
    (append-map (lambda (system)
                  (case subset
                    ((all)
                     ;; Build everything, including replacements.
                     (let ((all (fold-packages
                                 (lambda (package result)
                                   (if (package-replacement package)
                                       (cons* package
                                              (package-replacement package)
                                              result)
                                       (cons package result)))
                                 '()))
                           (job (lambda (package)
                                  (package->job store package
                                                system))))
                       (append (filter-map job all)
                               (qemu-jobs store system)
                               (tarball-jobs store system)
                               (cross-jobs system))))
                    ((core)
                     ;; Build core packages only.
                     (append (map (lambda (package)
                                    (package-job store (job-name package)
                                                 package system))
                                  %core-packages)
                             (cross-jobs system)))
                    (else
                     (error "unknown subset" subset))))
                %hydra-supported-systems)))
