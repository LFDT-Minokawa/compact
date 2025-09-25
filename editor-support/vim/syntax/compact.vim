" This file is part of Compact.
" Copyright (C) 2025 Midnight Foundation
" SPDX-License-Identifier: Apache-2.0
" Licensed under the Apache License, Version 2.0 (the "License");
" you may not use this file except in compliance with the License.
" You may obtain a copy of the License at
"
" 	http://www.apache.org/licenses/LICENSE-2.0
"
" Unless required by applicable law or agreed to in writing, software
" distributed under the License is distributed on an "AS IS" BASIS,
" WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
" See the License for the specific language governing permissions and
" limitations under the License.

if exists("b:current_syntax")
  finish
endif

syn keyword compactKeyword as assert circuit constructor contract default disclose enum export import include ledger module pad pragma prefix pure return sealed slice struct witness
syn keyword compactBoolean true false
syn keyword compactType Boolean Bytes Opaque Field Vector Uint
syn keyword compactType Kernel Counter Set Map List MerkleTree HistoricMerkleTree
syn keyword compactConditional if else 
syn keyword compactStorageClass const
syn match compactOperator "="
syn match compactOperator "+="
syn match compactOperator "-="
syn match compactOperator "!"
syn match compactOperator "."
syn match compactOperator ".."
syn match compactOperator "#"
syn match compactOperator "+"
syn match compactOperator "*"
syn match compactOperator "-"
syn match compactOperator "?"
syn match compactOperator ":"
syn match compactOperator "&&"
syn match compactOperator "||"
syn match compactOperator "=="
syn match compactOperator "!="
syn match compactOperator "<"
syn match compactOperator "<="
syn match compactOperator ">"
syn match compactOperator ">="
syn match compactOperator "=>"
syn keyword compactRepeat map fold for of
syn keyword compactTodo contained TODO FIXME XXX NOTE
syn match compactComment "//.*$" contains=compactTodo
syn region compactComment start="/\*" end="\*/" contains=compactTodo
syn region compactString start="\"" skip="\\\\\|\\\"" end="\""
syn match compactIdentifier '[a-zA-Z_$][a-zA-Z0-9_$]*'
syn match compactNumber '\d\+'

let b:current_syntax = "compact"

hi def link compactKeyword Keyword
hi def link compactBoolean Boolean
hi def link compactType Type
hi def link compactConditional Conditional
hi def link compactStorageClass StorageClass
hi def link compactOperator Operator
hi def link compactRepeat Repeat
hi def link compactTodo Todo
hi def link compactComment Comment
hi def link compactNumber Number
hi def link compactString String
