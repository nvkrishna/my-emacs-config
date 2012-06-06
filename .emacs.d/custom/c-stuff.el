;; This is a file that stores my C related config

;;enable Yasnippet 
(add-to-list 'load-path "~/.emacs.d/elpa/yasnippet-0.6.1/")
(require 'yasnippet)
(yas/initialize)
(setq yas/root-directory '("~/.emacs.d/snippets"
						   "~/.emacs.d/elpa/yasnippet-0.6.1/snippets"))
(mapc 'yas/load-directory yas/root-directory)
 
;In developer's world, tab is just made of spaces 
(setq-default indent-tabs-mod nil)
(setq-default tab-width 4)
(setq indent-line-function 'insert-tab)

;include decoration stuff
(show-paren-mode 1)
(delete-selection-mode 1)

;code browsing aesthetics
(setq c-default-style "linux" c-basic-offset 4)


;All Hail the emacs CEDET
(load-file "~/.emacs.d/elpa/cedet-1.0/common/cedet.el")
(require 'semantic-sb)
(require 'semantic-ia)
(require 'eassist)



(global-srecode-minor-mode 1)
(semantic-load-enable-gaudy-code-helpers)
(defun cedet-c-mode-hook ()
  (local-set-key  "." 'semantic-complete-self-insert)
  (local-set-key  ">" 'semantic-complete-self-insert)
  (local-set-key (kbd "C-c s s") 'semantic-ia-show-summary)
  (local-set-key (kbd "C-c s d") 'semantic-ia-show-doc)
  (local-set-key (kbd "C-c t") (lambda () (interactive) (yas/insert-snippet))))
(add-hook 'c-mode-hook 'cedet-c-mode-hook)

;system header files
(require 'semantic-gcc)

(add-to-list 'load-path "~/.emacs.d/elpa/ecb-2.40/")
(require 'ecb-autoloads)

(custom-set-variables
  ;; custom-set-variables was added by Custom.
  ;; If you edit it by hand, you could mess it up, so be careful.
  ;; Your init file should contain only one such instance.
  ;; If there is more than one, they won't work right.
 '(ecb-options-version "2.40")
 '(ecb-tree-indent 2))

;;enable auto-complete 
(add-to-list 'load-path "~/.emacs.d/elpa/auto-complete-1.4/")
(require 'auto-complete)

(add-to-list 'load-path "~/.emacs.d/custom/")
(require 'auto-complete-semantic)
(require 'auto-complete-yasnippet)
(require 'auto-complete-python)
