(define-module (gnu packages findent)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (gnu packages linux))

(define-public findent
  (package
    (name "findent")
    (version "3.1.7")
    (source
     (origin
       (method url-fetch)
       (uri
        (string-append "https://sourceforge.net/projects/"
                       name "/files/"
                       name "-"
                       version ".tar.gz"))
       (sha256
        (base32 "1chby3jakf1yfdbvxjmsn97rz0ln6njkm9wgs57v8jy1h3yz7fs2"))))
    (build-system gnu-build-system)
    (native-inputs
     `(("util-linux" ,util-linux)))
    (arguments
     `(#:phases (modify-phases %standard-phases
                  (add-after 'unpack 'patch-sources
                    (lambda _
                      (substitute* (find-files "." "\\.sh$")
                        (("/bin/sh") (which "sh"))))))))
    (home-page
     "https://sourceforge.net/projects/findent/")
    (synopsis "Indent, beautify Fortran source, generates dependencies")
    (description "findent is an indenter for Fortran programs, fixed and free format.
   findent can also translate fixed format to free format and vice versa.
   Since version 3.0.0, findent can generate dependencies based on USE,
   MODULE, SUBMODULE, INCLUDE, #include, ??include  and emit a sh script
   that, using findent, creates a dependency file to be used in a Makefile.")
    (license license:bsd-3)))
