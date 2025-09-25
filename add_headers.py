# This file is part of Compact.
# Copyright (C) 2025 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict

# basic logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)


class HeaderManager:

    def __init__(self, config_path: str, directory: str):
        self.config = self._load_config(config_path)
        self.prefixes = self.config.get("prefixes", {})
        self.excluded_directories = self.config.get("excluded_directories", [])
        self.excluded_files = self.config.get("excluded_files", [])
        self.header_template = self.config.get("header_template", "")
        self.company_name = "Midnight Foundation"
        self.root_directory = directory
        self.processed_files = 0
        self.total_files = 0

    @staticmethod
    def _load_config(config_path) -> Dict:
        try:
            with open(config_path, 'r', encoding='utf-8') as file:
                return json.load(file)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            logging.error("-> error loading configuration: %s", e)
            return {}

    def _filter_files_and_directories(self) -> list[Path]:
        result = []

        for dir_path, dir_names, filenames in os.walk(self.root_directory):
            dir_names[:] = [d for d in dir_names if d not in self.excluded_directories]

            for dirname in dir_names:
                result.append(Path(dir_path) / dirname)

            for filename in filenames:
                if filename not in self.excluded_files:
                    logging.info(f"-> adding file: {filename}")
                    result.append(Path(dir_path) / filename)

        return result

    def _filter_extensions(self) -> Dict:

        filtered_files = self._filter_files_and_directories()
        filtered_dictionary = {}

        for prefix, content in self.prefixes.items():
            extensions = content.get("extensions", [])
            special_cases = content.get("special_cases", [])
            
            temp_filtered_files = [f for f in filtered_files if f.suffix in extensions or f.name in special_cases]
            filtered_dictionary[prefix] = temp_filtered_files

        return filtered_dictionary

    def _format_license_header(self, prefix: str, year: str) -> str:
        filled = self.header_template.replace("[YEAR]", year).replace("[COMPANY]", self.company_name)
        return '\n'.join(f"{prefix} {line}" if line else prefix for line in filled.splitlines())

    def _scan_for_header(self, prefix: str, content: str) -> bool:

        template_lines = self.header_template.strip().splitlines()

        regex_lines = []
        for line in template_lines:
            escaped = re.escape(line)
            escaped = escaped.replace(r"\[YEAR\]", r"\d{4}")
            escaped = escaped.replace(r"\[COMPANY\]", re.escape(self.company_name))
            regex_lines.append(re.escape(prefix) + r"\s?" + escaped)

        full_pattern = r"\n".join(regex_lines)
        header_regex = re.compile(full_pattern, re.MULTILINE)

        return bool(header_regex.search(content))

    @staticmethod
    def _get_insert_index(lines: list[str]) -> int:
        index = 0
        while index < len(lines) and lines[index].startswith("#!"):
            index += 1
        return index

    def _save_header_to_file(self, prefix: str, file_path: Path, header: str):

        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')

            if self._scan_for_header(prefix, content):
                logging.info(f"-> header already exists (date may vary): {file_path}")
                return

            lines = content.splitlines()
            insert_index = self._get_insert_index(lines)

            new_lines = []

            # preserve shebang
            if insert_index > 0:
                new_lines.extend(lines[:insert_index])
                new_lines.append("")

            # header
            new_lines.extend(header.strip().splitlines())

            # ensure empty line after header
            if insert_index < len(lines):
                if lines[insert_index].strip() != "":
                    new_lines.append("")

            new_lines.extend(lines[insert_index:])

            file_path.write_text('\n'.join(new_lines) + '\n', encoding='utf-8')
            logging.info(f"-> header added to: {file_path}")
            self.processed_files += 1

        except Exception as e:
            logging.error(f"-> failed to process: {file_path}: {e}")

    def add_headers(self):

        filtered_files = self._filter_extensions()
        current_year = str(datetime.now().year)

        for prefix, files in filtered_files.items():
            header = self._format_license_header(prefix, current_year)
            for file in files:
                self._save_header_to_file(prefix, file, header)
                self.total_files += 1

        logging.info(f"-> total files: {self.total_files}")
        logging.info(f"-> processed files: {self.processed_files}")


def main():
    header_manager = HeaderManager("header_config.json", ".")
    header_manager.add_headers()


if __name__ == "__main__":
    main()
