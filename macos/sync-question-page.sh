#!/bin/bash
# Rebuilds Sources/Margin/QuestionPage.swift from ../shared/question.html (the page both apps use to draw a question).
set -euo pipefail
cd "$(dirname "$0")"
{
  echo '// Generated from shared/question.html. Edit that file and run ./sync-question-page.sh, not this one.'
  echo 'enum QuestionPage {'
  echo '    static let html = #"""'
  cat ../shared/question.html
  echo '"""#'
  echo '}'
} > Sources/Margin/QuestionPage.swift
echo "Updated Sources/Margin/QuestionPage.swift"
