;;; ob-exp.el --- Exportation of org-babel source blocks

;; Copyright (C) 2009-2011  Free Software Foundation, Inc.

;; Author: Eric Schulte
;;	Dan Davison
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:
(require 'ob)
(require 'org-exp-blocks)
(eval-when-compile
  (require 'cl))

(defvar obe-marker nil)
(defvar org-current-export-file)
(defvar org-babel-lob-one-liner-regexp)
(defvar org-babel-ref-split-regexp)
(declare-function org-babel-lob-get-info "ob-lob" ())
(declare-function org-babel-eval-wipe-error-buffer "ob-eval" ())
(add-to-list 'org-export-interblocks '(src org-babel-exp-inline-src-blocks))
(add-to-list 'org-export-interblocks '(lob org-babel-exp-lob-one-liners))
(add-hook 'org-export-blocks-postblock-hook 'org-exp-res/src-name-cleanup)

(org-export-blocks-add-block '(src org-babel-exp-src-block nil))

(defcustom org-export-babel-evaluate t
  "Switch controlling code evaluation during export.
When set to nil no code will be evaluated as part of the export
process."
  :group 'org-babel
  :type 'boolean)
(put 'org-export-babel-evaluate 'safe-local-variable (lambda (x) (eq x nil)))

(defmacro org-babel-exp-in-export-file (lang &rest body)
  (declare (indent 1))
  `(let* ((lang-headers (intern (concat "org-babel-default-header-args:" ,lang)))
	  (heading (nth 4 (ignore-errors (org-heading-components))))
	  (link (when org-current-export-file
		  (org-make-link-string
		   (if heading
		       (concat org-current-export-file "::" heading)
		     org-current-export-file))))
	  (export-buffer (current-buffer)) results)
     (when link
       ;; resolve parameters in the original file so that
       ;; headline and file-wide parameters are included, attempt
       ;; to go to the same heading in the original file
       (set-buffer (get-file-buffer org-current-export-file))
       (save-restriction
	 (condition-case nil
	     (let ((org-link-search-inhibit-query t))
	       (org-open-link-from-string link))
	   (error (when heading
		    (goto-char (point-min))
		    (re-search-forward (regexp-quote heading) nil t))))
	 (setq results ,@body))
       (set-buffer export-buffer)
       results)))
(def-edebug-spec org-babel-exp-in-export-file (form body))

(defun org-babel-exp-src-block (body &rest headers)
  "Process source block for export.
Depending on the 'export' headers argument in replace the source
code block with...

both ---- display the code and the results

code ---- the default, display the code inside the block but do
          not process

results - just like none only the block is run on export ensuring
          that it's results are present in the org-mode buffer

none ----- do not display either code or results upon export"
  (interactive)
  (unless noninteractive (message "org-babel-exp processing..."))
  (save-excursion
    (goto-char (match-beginning 0))
    (let* ((info (org-babel-get-src-block-info 'light))
	   (lang (nth 0 info))
	   (raw-params (nth 2 info)) hash)
      ;; bail if we couldn't get any info from the block
      (when info
	;; if we're actually going to need the parameters
	(when (member (cdr (assoc :exports (nth 2 info))) '("both" "results"))
	  (org-babel-exp-in-export-file lang
	    (setf (nth 2 info)
		  (org-babel-process-params
		   (org-babel-merge-params
		    org-babel-default-header-args
		    (org-babel-params-from-properties lang)
		    (if (boundp lang-headers) (eval lang-headers) nil)
		    raw-params))))
	  (setf hash (org-babel-sha1-hash info)))
	;; expand noweb references in the original file
	(setf (nth 1 info)
	      (if (and (cdr (assoc :noweb (nth 2 info)))
		       (string= "yes" (cdr (assoc :noweb (nth 2 info)))))
		  (org-babel-expand-noweb-references
		   info (get-file-buffer org-current-export-file))
		(nth 1 info)))
	(org-babel-exp-do-export info 'block hash)))))

(defun org-babel-exp-inline-src-blocks (start end)
  "Process inline source blocks between START and END for export.
See `org-babel-exp-src-block' for export options, currently the
options and are taken from `org-babel-default-inline-header-args'."
  (interactive)
  (save-excursion
    (goto-char start)
    (while (and (< (point) end)
                (re-search-forward org-babel-inline-src-block-regexp end t))
      (let* ((info (save-match-data (org-babel-parse-inline-src-block-match)))
	     (params (nth 2 info)))
	(save-match-data
	  (goto-char (match-beginning 2))
	  (unless (org-babel-in-example-or-verbatim)
	    ;; expand noweb references in the original file
	    (setf (nth 1 info)
		  (if (and (cdr (assoc :noweb params))
			   (string= "yes" (cdr (assoc :noweb params))))
		      (org-babel-expand-noweb-references
		       info (get-file-buffer org-current-export-file))
		    (nth 1 info)))
	    (let ((code-replacement (save-match-data
				      (org-babel-exp-do-export info 'inline))))
	      (if code-replacement
		  (replace-match code-replacement nil nil nil 1)
		(org-babel-examplize-region (match-beginning 1) (match-end 1))
		(forward-char 2)))))))))

(defun org-exp-res/src-name-cleanup ()
  "Clean up #+results and #+name lines for export.
This function should only be called after all block processing
has taken place."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (org-re-search-forward-unprotected
	    (concat
	     "\\("org-babel-src-name-regexp"\\|"org-babel-result-regexp"\\)")
	    nil t)
      (delete-region
       (progn (beginning-of-line) (point))
       (progn (end-of-line) (+ 1 (point)))))))

(defun org-babel-in-example-or-verbatim ()
  "Return true if point is in example or verbatim code.
Example and verbatim code include escaped portions of
an org-mode buffer code that should be treated as normal
org-mode text."
  (or (save-match-data
	(save-excursion
	  (goto-char (point-at-bol))
	  (looking-at "[ \t]*:[ \t]")))
      (org-in-verbatim-emphasis)
      (org-in-block-p org-list-forbidden-blocks)
      (org-between-regexps-p "^[ \t]*#\\+begin_src" "^[ \t]*#\\+end_src")))

(defvar org-babel-default-lob-header-args)
(defun org-babel-exp-lob-one-liners (start end)
  "Process Library of Babel calls between START and END for export.
See `org-babel-exp-src-block' for export options. Currently the
options are taken from `org-babel-default-header-args'."
  (interactive)
  (save-excursion
    (goto-char start)
    (while (and (< (point) end)
		(re-search-forward org-babel-lob-one-liner-regexp nil t))
      (unless (and (match-string 12) (org-babel-in-example-or-verbatim))
	(let* ((lob-info (org-babel-lob-get-info))
	       (inlinep (match-string 11))
	       (inline-start (match-end 11))
	       (inline-end (match-end 0))
	       (rep (let ((lob-info (org-babel-lob-get-info)))
		      (save-match-data
			(org-babel-exp-do-export
			 (list "emacs-lisp" "results"
			       (org-babel-merge-params
				org-babel-default-header-args
				org-babel-default-lob-header-args
				(org-babel-params-from-properties)
				(org-babel-parse-header-arguments
				 (org-babel-clean-text-properties
				  (concat ":var results="
					  (mapconcat #'identity
						     (butlast lob-info) " ")))))
			       "" nil (car (last lob-info)))
			 'lob)))))
	  (setq end (+ end (- (length rep)
			      (- (length (match-string 0))
				 (length (or (match-string 11) ""))))))
	  (if inlinep
	      (save-excursion
		(goto-char inline-start)
		(delete-region inline-start inline-end)
		(insert rep))
	    (replace-match rep t t)))))))

(defun org-babel-exp-do-export (info type &optional hash)
  "Return a string with the exported content of a code block.
The function respects the value of the :exports header argument."
  (flet ((silently () (let ((session (cdr (assoc :session (nth 2 info)))))
			(when (not (and session (equal "none" session)))
			  (org-babel-exp-results info type 'silent))))
	 (clean () (unless (eq type 'inline) (org-babel-remove-result info))))
    (case (intern (or (cdr (assoc :exports (nth 2 info))) "code"))
      ('none (silently) (clean) "")
      ('code (silently) (clean) (org-babel-exp-code info))
      ('results (org-babel-exp-results info type nil hash) "")
      ('both (org-babel-exp-results info type nil hash)
	     (org-babel-exp-code info)))))

(defun org-babel-exp-code (info)
  "Return the original code block formatted for export."
  (org-fill-template
   "#+BEGIN_SRC %lang%flags\n%body\n#+END_SRC"
   `(("lang"  . ,(nth 0 info))
     ("flags" . ,((lambda (f) (when f (concat " " f))) (nth 3 info)))
     ("body"  . ,(nth 1 info)))))

(defun org-babel-exp-results (info type &optional silent hash)
  "Evaluate and return the results of the current code block for export.
Results are prepared in a manner suitable for export by org-mode.
This function is called by `org-babel-exp-do-export'.  The code
block will be evaluated.  Optional argument SILENT can be used to
inhibit insertion of results into the buffer."
  (when (and org-export-babel-evaluate
	     (not (and hash (equal hash (org-babel-current-result-hash)))))
    (let ((lang (nth 0 info))
	  (body (nth 1 info)))
      ;; skip code blocks which we can't evaluate
      (when (fboundp (intern (concat "org-babel-execute:" lang)))
	(org-babel-eval-wipe-error-buffer)
	(prog1 nil
	  (setf (nth 2 info)
		(org-babel-exp-in-export-file lang
		  (org-babel-process-params
		   (org-babel-merge-params
		    (nth 2 info)
		    `((:results . ,(if silent "silent" "replace")))))))
	  (cond
	   ((equal type 'block)
	    (org-babel-execute-src-block nil info))
	   ((equal type 'inline)
	    ;; position the point on the inline source block allowing
	    ;; `org-babel-insert-result' to check that the block is
	    ;; inline
	    (re-search-backward "[ \f\t\n\r\v]" nil t)
	    (re-search-forward org-babel-inline-src-block-regexp nil t)
	    (re-search-backward "src_" nil t)
	    (org-babel-execute-src-block nil info))
	   ((equal type 'lob)
	    (save-excursion
	      (re-search-backward org-babel-lob-one-liner-regexp nil t)
	      (org-babel-execute-src-block nil info)))))))))

(provide 'ob-exp)



;;; ob-exp.el ends here
