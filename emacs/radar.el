;;; radar.el --- Research Radar 日报：结构化阅读 + 就地打标 -*- lexical-binding: t; -*-

;; Keywords: tools, convenience
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; 在 Emacs 里读 Research Radar 的每日日报：
;;
;;   M-x radar          打开最新一天；C-u M-x radar 选日期
;;
;; 与 TUI 对齐：
;;   - special-mode 结构化缓冲（**不是** markdown-mode）：标题/字段/链接各有 face
;;   - 「标记：」行渲染成可点按钮（like/dislike/confused/save|learned），点一下切换
;;   - [ / ] 切前一天/后一天，n / p 跳条目，g 重读文件，? 打开菜单，C 进 opencode 细聊
;;
;; 加载：把 <repo>/emacs 加入 `load-path' 后 (require 'radar)。

;;; Code:

(require 'button)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'transient)

(defgroup radar nil
  "Research Radar 日报。"
  :group 'tools
  :prefix "radar-")

(defcustom radar-repo-root
  (or (and load-file-name
           (file-name-directory
            (directory-file-name (file-name-directory load-file-name))))
      (expand-file-name "~/github-project/research-radar"))
  "Research Radar 仓库根目录。"
  :type 'directory
  :group 'radar)

(defcustom radar-open-program "bin/radar-open"
  "打开链接用的脚本（相对 `radar-repo-root'）；会顺带把浏览器窗口置顶。"
  :type 'string
  :group 'radar)

;;; Faces -------------------------------------------------------------

(defface radar-section-face
  '((t :inherit outline-1 :weight bold))
  "栏目标题。"
  :group 'radar)

(defface radar-item-face
  '((t :inherit outline-2 :weight bold))
  "条目标题。"
  :group 'radar)

(defface radar-field-face
  '((t :inherit default :weight bold))
  "字段名。"
  :group 'radar)

(defface radar-link-face
  '((t :inherit link))
  "链接。"
  :group 'radar)

(defface radar-mark-on-face
  '((t :inherit success :weight bold))
  "已选中的标记。"
  :group 'radar)

(defface radar-mark-off-face
  '((t :inherit shadow))
  "未选中的标记。"
  :group 'radar)

;;; 配置 / 路径 -------------------------------------------------------

(defun radar--config-file () (expand-file-name "config.toml" radar-repo-root))

(defun radar--slurp (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun radar--general (key &optional default)
  "读 config.toml 的 [general] KEY。"
  (let ((ans default) (sec nil))
    (when (file-readable-p (radar--config-file))
      (dolist (raw (split-string (radar--slurp (radar--config-file)) "\n"))
        (let ((line (string-trim raw)))
          (cond
           ((string-match "\\`\\[\\([^]]+\\)\\]" line)
            (setq sec (match-string 1 line)))
           ((and (equal sec "general")
                 (string-match (concat "\\`" (regexp-quote key)
                                       "[ \t]*=[ \t]*\"?\\([^\"\n]*\\)") line))
            (setq ans (string-trim (match-string 1 line))))))))
    ans))

(defun radar--data-root () (expand-file-name (or (radar--general "data_dir") "data") radar-repo-root))
(defun radar--digest-dir () (expand-file-name (or (radar--general "digest_dir") "digest") (radar--data-root)))
(defun radar--state-dir () (expand-file-name (or (radar--general "state_dir") "state") (radar--data-root)))

(defun radar--queue-prefixes ()
  "config.toml 里 kind=\"queue\" 栏目的 prefix 列表。"
  (let ((blocks nil) (res nil))
    (when (file-readable-p (radar--config-file))
      (setq blocks (cdr (split-string (radar--slurp (radar--config-file))
                                      "\\[\\[sections\\]\\]"))))
    (dolist (b blocks)
      (when (and (string-match "^[ \t]*kind[ \t]*=[ \t]*\"queue\"" b)
                 (string-match "^[ \t]*prefix[ \t]*=[ \t]*\"\\([^\"]+\\)\"" b))
        (push (match-string 1 b) res)))
    res))

(defun radar--digests ()
  "所有日报 md（按日期升序）。"
  (let ((dir (radar--digest-dir)))
    (when (file-directory-p dir)
      (sort (directory-files-recursively dir "\\.md\\'") #'string<))))

(defun radar--find-digest (date files)
  (seq-find (lambda (f) (equal (file-name-base f) date)) files))

(defun radar--lines (file)
  "读 FILE 为行列表（去掉末尾空行，保留中间空行）。"
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-max))
    (skip-chars-backward " \t\n\r")
    (delete-region (point) (point-max))
    (let ((s (buffer-string)))
      (if (string-empty-p s) nil (split-string s "\n" nil)))))

(defun radar--write-lines (file lines)
  (let ((tmp (concat file ".tmp")))
    (with-temp-buffer
      (insert (mapconcat #'identity lines "\n") "\n")
      (write-region (point-min) (point-max) tmp nil 'silent))
    (rename-file tmp file t)))

;;; 解析 -------------------------------------------------------------

(cl-defstruct (radar-item (:constructor radar--make-item))
  prefix num title head mark end tokens)

(cl-defstruct (radar-section (:constructor radar--make-section))
  title items)

(defun radar--parse (lines)
  "把日报行列表解析成 (SECTIONS . ITEMS)。"
  (let ((secs nil) (sec nil) (item nil) (items nil) (i 0) (n (length lines)))
    (dolist (ln lines)
      (let ((trimmed (string-trim-right ln)))
        (cond
         ((string-match "\\`## +\\(.+\\)" trimmed)
          (when item (setf (radar-item-end item) i) (push item items) (setq item nil))
          (setq sec (radar--make-section :title (string-trim (match-string 1 trimmed)) :items nil))
          (push sec secs))
         ((and sec (string-match "\\`### +\\[\\([A-Za-z]+\\)\\([0-9]+\\)\\] +\\(.*\\)" trimmed))
          (when item (setf (radar-item-end item) i) (push item items))
          (setq item (radar--make-item :prefix (match-string 1 trimmed)
                                       :num (string-to-number (match-string 2 trimmed))
                                       :title (string-trim (match-string 3 trimmed))
                                       :head i :end n))
          (push item (radar-section-items sec)))
         ((and item (string-match "\\`- +\\*\\*标记\\*\\*：\\(.*\\)" trimmed))
          (setf (radar-item-mark item) i)
          (setf (radar-item-tokens item)
                (split-string (string-trim (match-string 1 trimmed)) "[ \t]+" t)))))
      (setq i (1+ i)))
    (when item (setf (radar-item-end item) i) (push item items))
    (dolist (s secs)
      (setf (radar-section-items s) (nreverse (radar-section-items s))))
    (list (nreverse secs) (nreverse items))))

;;; 渲染 -------------------------------------------------------------

(defvar-local radar--file nil)
(defvar-local radar--files nil)
(defvar-local radar--index 0)
(defvar-local radar--items nil)

(defun radar--header ()
  (format " Research Radar · %s  (%d/%d) "
          (file-name-base (or radar--file ""))
          (1+ radar--index) (length radar--files)))

(defun radar--plain (s)
  (replace-regexp-in-string "\\*\\*\\(.+?\\)\\*\\*" "\\1" s))

(defun radar--link-target (link)
  "把 md 里的链接解析成可打开的目标。
http(s) 原样返回；其它（`file:' 或相对文件名，如“标题.pdf”）按“相对日报目录”解析成本地路径。"
  (let ((link (string-trim link)))
    (cond
     ((string-prefix-p "file://" link) (substring link 7))
     ((string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*://" link) link)
     (t (expand-file-name link (file-name-directory (or radar--file default-directory)))))))

(defun radar--insert-link (text link)
  (let* ((target (radar--link-target link))
         (beg (point)))
    (insert-button text
                   'action (let ((t2 target)) (lambda (_) (radar-open-url t2)))
                   'follow-link t
                   'help-echo (format "打开 %s" link)
                   'face 'radar-link-face)
    (put-text-property beg (point) 'radar-url target)))

(defun radar--insert-inline (s)
  (let ((pos 0))
    (while (string-match "\\[\\([^]]+\\)\\](\\([^)]+\\))" s pos)
      (insert (radar--plain (substring s pos (match-beginning 0))))
      (radar--insert-link (match-string 1 s) (match-string 2 s))
      (setq pos (match-end 0)))
    (insert (radar--plain (substring s pos)))))

(defun radar--marks-for (item)
  (if (member (radar-item-prefix item) (radar--queue-prefixes))
      '("like" "dislike" "confused" "learned")
    '("like" "dislike" "confused" "save")))

(defun radar--insert-marks (item)
  (insert (propertize "    标记：" 'face 'radar-field-face))
  (let ((toks (radar-item-tokens item)))
    (dolist (tok (radar--marks-for item))
      (let ((on (and (member tok toks) t)))
        (insert-button (format "[%s%s]" (if on "✔" " ") tok)
                       'action (let ((it item) (k tok))
                                 (lambda (_) (radar-toggle-mark it k)))
                       'follow-link t
                       'help-echo (format "%s %s" (if on "取消" "标记") tok)
                       'face (if on 'radar-mark-on-face 'radar-mark-off-face))
        (insert " ")))))

(defun radar--insert-item (item lines)
  (let ((start (point))
        (body (seq-subseq lines (radar-item-head item) (radar-item-end item))))
    (dolist (ln body)
      (cond
       ((string-match "\\`### +" ln)
        (insert (propertize (format "[%s%d] %s"
                                    (radar-item-prefix item) (radar-item-num item)
                                    (radar-item-title item))
                            'face 'radar-item-face)))
       ((string-match "\\`- +\\*\\*标记\\*\\*：" ln)
        (radar--insert-marks item))
       ((string-match "\\`- +\\*\\*\\(.+?\\)\\*\\*：\\(.*\\)" ln)
        (insert (propertize (format "    %s：" (match-string 1 ln)) 'face 'radar-field-face))
        (radar--insert-inline (match-string 2 ln)))
       (t (radar--insert-inline ln)))
      (insert "\n"))
    (put-text-property start (point) 'radar-item item)))

(defun radar--render ()
  "按 `radar--file' 重画整个缓冲。"
  (let ((inhibit-read-only t)
        (lines (radar--lines radar--file)))
    (erase-buffer)
    (pcase-let ((`(,secs ,items) (radar--parse lines)))
      (setq radar--items items)
      (dolist (sec secs)
        (insert (propertize (concat "▍ " (radar-section-title sec)) 'face 'radar-section-face) "\n\n")
        (dolist (it (radar-section-items sec))
          (radar--insert-item it lines))
        (insert "\n")))
    (delete-char -1)
    (goto-char (point-min))))

(defun radar--item-at-point ()
  (or (get-text-property (point) 'radar-item)
      (and (> (point) (point-min)) (get-text-property (1- (point)) 'radar-item))))

(defun radar--goto-item (prefix num)
  (goto-char (point-min))
  (when (re-search-forward (format "^\\[%s%d\\] " (regexp-quote prefix) num) nil t)
    (goto-char (match-beginning 0))))

(defun radar--goto-mark (prefix num token)
  "渲染后把光标放回「同一标记按钮」上，别跳到条目标题。"
  (radar--goto-item prefix num)
  (let ((end (or (next-single-property-change (point) 'radar-item) (point-max))))
    (when (re-search-forward (format "\\[.?%s\\]" (regexp-quote token)) end t)
      (goto-char (match-beginning 0)))))

;;; 交互 -------------------------------------------------------------

(defconst radar--item-regexp "^\\[\\([A-Za-z]+\\)\\([0-9]+\\)\\] ")

(defun radar-next-item ()
  "跳到下一条目。"
  (interactive)
  (when (re-search-forward radar--item-regexp nil t)
    (goto-char (match-beginning 0))))

(defun radar-prev-item ()
  "跳到上一条目。"
  (interactive)
  (let ((p (save-excursion (beginning-of-line) (re-search-backward radar--item-regexp nil t))))
    (goto-char (or p (point-min)))))

(defun radar-open-link-at-point ()
  "打开光标所在行的链接。"
  (interactive)
  (let ((url (get-text-property (point) 'radar-url)))
    (if url (radar-open-url url) (message "这一行没有链接"))))

(defun radar-open-url (target)
  "打开 TARGET：http(s) 走 radar-open（置顶浏览器）；本地文件/目录走 xdg-open。
本地路径不存在时直接报错，不把它丢给 xdg-open（否则 KDE 会弹 KIO 报错）。"
  (interactive "s打开: ")
  (let ((script (expand-file-name radar-open-program radar-repo-root)))
    (cond
     ((string-match-p "\\`https?://" target)
      (if (file-executable-p script)
          (progn (start-process "radar-open" "*radar-open*" script target)
                 (message "已打开：%s" target))
        (browse-url target)))
     ((file-exists-p target)
      (start-process "radar-open" "*radar-open*" script target)
      (message "已打开：%s" (file-name-nondirectory (directory-file-name target))))
     (t (user-error "打不开（文件不存在）：%s" target)))))

(defun radar-open-folder ()
  "打开当天日报所在文件夹。"
  (interactive)
  (start-process "radar-open" "*radar-open*"
                 (expand-file-name radar-open-program radar-repo-root)
                 (file-name-directory radar--file)))

(defun radar-mark-at-point (token)
  "给光标所在条目切换 TOKEN 标记。"
  (let ((item (radar--item-at-point)))
    (if item (radar-toggle-mark item token)
      (message "这一行不属于任何条目"))))

(defun radar-toggle-mark (item token)
  "切换 ITEM 的 TOKEN 标记并写回 md。"
  (interactive (let ((it (radar--item-at-point)))
                 (unless it (user-error "这里没有条目"))
                 (list it (completing-read "标记: " (radar--marks-for it) nil t))))
  (let* ((file radar--file)
         (lines (radar--lines file))
         (mark (radar-item-mark item))
         (at (radar-item-end item)))
    (if mark
        (let* ((cur (radar-item-tokens item))
               (new (if (member token cur) (delete token cur) (append cur (list token)))))
          (setf (nth mark lines) (format "- **标记**：%s" (string-join new " "))))
      (setq lines (append (seq-subseq lines 0 at)
                          (list (format "- **标记**：%s" token))
                          (seq-subseq lines at))))
    (radar--write-lines file lines)
    (radar--render)
    (radar--goto-mark (radar-item-prefix item) (radar-item-num item) token)
    (let ((now (radar--item-at-point)))
      (message "%s%d 标记：%s" (radar-item-prefix item) (radar-item-num item)
               (if now (string-join (radar-item-tokens now) " ") "无")))))

(defun radar-apply ()
  "把缓冲里的标记应用进反馈（调用 bin/radar-fb parse）。"
  (interactive)
  (let ((script (expand-file-name "bin/radar-fb" radar-repo-root)))
    (if (not (file-executable-p script))
        (message "找不到 bin/radar-fb")
      (let ((default-directory (file-name-as-directory radar-repo-root)))
        (with-temp-buffer
          (call-process script nil t nil "parse")
          (message "%s" (or (car (last (split-string (string-trim (buffer-string)) "\n" t)))
                            "已应用")))))))

(defun radar--goto-day (delta)
  (let ((i (+ radar--index delta)))
    (if (and (>= i 0) (< i (length radar--files)))
        (progn
          (setq radar--file (nth i radar--files) radar--index i)
          (radar--render)
          (goto-char (point-min))
          (message "→ %s" (file-name-base radar--file)))
      (message "没有更%s的日报了" (if (< delta 0) "早" "新")))))

(defun radar-prev-day () (interactive) (radar--goto-day -1))
(defun radar-next-day () (interactive) (radar--goto-day 1))

(defun radar-revert ()
  "重新从磁盘读取当前日报。"
  (interactive)
  (setq radar--files (radar--digests)
        radar--index (or (cl-position radar--file radar--files :test #'equal) radar--index))
  (radar--render)
  (message "已重新读取 %s" (file-name-base radar--file)))

(defun radar--session-id (date)
  "当天日报在本机生成的 opencode session id；若不是本机生成则 nil。"
  (let ((f (expand-file-name (format "sessions/%s.id" date) (radar--state-dir)))
        (host (car (split-string (or (system-name) "") "\\."))))
    (when (file-readable-p f)
      (let* ((txt (string-trim (radar--slurp f)))
             (parts (split-string txt "\t")))
        (when (and (= (length parts) 2)
                   (equal (car (split-string (car parts) "\\.")) host)
                   (string-prefix-p "ses" (cadr parts)))
          (cadr parts))))))

(defcustom radar-agent-config-maker 'agent-shell-opencode-make-agent-config
  "生成 agent-shell 配置的函数（默认 OpenCode，因为日报 session 是它建的）。"
  :type 'function
  :group 'radar)

(defun radar-chat ()
  "进入 opencode 细聊：续当天生成日报的 session（本机生成时）。

agent-shell 用 buffer 的 `default-directory' 作为 ACP 的 cwd，而 ACP 靠 cwd 匹配
session 所属项目——所以这里必须保证在仓库目录下运行（`radar--show' 已设好）。
显式传 OpenCode 的 config，避免弹“选择智能体”界面。"
  (interactive)
  (require 'agent-shell nil t)
  (let ((sid (radar--session-id (file-name-base radar--file)))
        (default-directory (file-name-as-directory radar-repo-root)))
    (cond
     ((and sid (fboundp 'agent-shell-start) (fboundp radar-agent-config-maker))
      (message "续 session %s …" sid)
      (agent-shell-start :config (funcall radar-agent-config-maker) :session-id sid))
     ((and sid (fboundp 'agent-shell-resume-session))
      (message "续 session %s …" sid)
      (agent-shell-resume-session sid))
     ((fboundp 'agent-shell)
      (message "本机没有该日报的 session，已开新会话（可把 %s 丢给它）"
               (file-relative-name radar--file radar-repo-root))
      (call-interactively #'agent-shell))
     (t (message "没装 agent-shell；可在终端跑 `opencode %s'" radar-repo-root)))))

;;; 菜单 / 模式 -------------------------------------------------------

(transient-define-prefix radar-menu ()
  "Research Radar 操作菜单。"
  [["条目"
    ("n" "下一条目" radar-next-item)
    ("p" "上一条目" radar-prev-item)
    ("RET" "打开链接" radar-open-link-at-point)
    ("o" "打开当天文件夹" radar-open-folder)]
   ["标记当前条目"
    ("l" "like" (lambda () (interactive) (radar-mark-at-point "like")))
    ("d" "dislike" (lambda () (interactive) (radar-mark-at-point "dislike")))
    ("c" "confused（看不懂）" (lambda () (interactive) (radar-mark-at-point "confused")))
    ("s" "save（收藏）" (lambda () (interactive) (radar-mark-at-point "save")))
    ("e" "learned（学会/归档）" (lambda () (interactive) (radar-mark-at-point "learned")))
    ("a" "应用标记（radar fb parse）" radar-apply)]
   ["日报"
    ("[" "前一天" radar-prev-day)
    ("]" "后一天" radar-next-day)
    ("g" "重新读取文件" radar-revert)
    ("C" "与 opencode 细聊" radar-chat)]])

(defvar radar-mode-map
  (let ((m (make-sparse-keymap)))
    (set-keymap-parent m special-mode-map)
    (define-key m (kbd "n") #'radar-next-item)
    (define-key m (kbd "p") #'radar-prev-item)
    (define-key m (kbd "TAB") #'radar-next-item)
    (define-key m (kbd "<backtab>") #'radar-prev-item)
    (define-key m (kbd "RET") #'radar-open-link-at-point)
    (define-key m (kbd "[") #'radar-prev-day)
    (define-key m (kbd "]") #'radar-next-day)
    (define-key m (kbd "g") #'radar-revert)
    (define-key m (kbd "?") #'radar-menu)
    (define-key m (kbd "C") #'radar-chat)
    (define-key m (kbd "a") #'radar-apply)
    (define-key m (kbd "o") #'radar-open-folder)
    (define-key m (kbd "l") (lambda () (interactive) (radar-mark-at-point "like")))
    (define-key m (kbd "d") (lambda () (interactive) (radar-mark-at-point "dislike")))
    (define-key m (kbd "c") (lambda () (interactive) (radar-mark-at-point "confused")))
    (define-key m (kbd "s") (lambda () (interactive) (radar-mark-at-point "save")))
    (define-key m (kbd "e") (lambda () (interactive) (radar-mark-at-point "learned")))
    m))

(define-derived-mode radar-mode special-mode "Radar"
  "Research Radar 日报阅读模式。"
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (setq-local header-line-format '(:eval (radar--header)))
  (setq-local revert-buffer-function (lambda (&rest _) (radar-revert))))

(defun radar--show (file)
  (let ((buf (get-buffer-create "*Research Radar*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'radar-mode) (radar-mode))
      ;; 关键：让 agent-shell / opencode 在这个 buffer 里以仓库为工作目录
      ;; （ACP 用 cwd 匹配 session 所属项目，否则 resume 会失败改开新会话）
      (setq default-directory (file-name-as-directory radar-repo-root))
      (setq radar--files (radar--digests)
            radar--index (or (cl-position file radar--files :test #'equal) 0)
            radar--file file)
      (radar--render)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;###autoload
(defun radar (&optional arg)
  "打开 Research Radar 日报。默认最新一天；带前缀参数 ARG 时选择日期。"
  (interactive "P")
  (let* ((all (radar--digests))
         (file (cond
                ((null all) (user-error "还没有日报（先运行 radar run）"))
                (arg (let* ((dates (mapcar #'file-name-base all))
                            (pick (completing-read "日期: " (reverse dates) nil t)))
                       (radar--find-digest pick all)))
                (t (car (last all))))))
    (radar--show file)))

(provide 'radar)
;;; radar.el ends here
