# Copyright (C) 2017 - 2021 Michael Fabian Dirks
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

# CMake Setup
cmake_minimum_required(VERSION 3.8...4.0)

################################################################################
# Options
################################################################################

set(CODESIGN_PATH "" CACHE PATH "Path to code signing tool (if not in environment).")
set(CODESIGN_ARGS "" CACHE STRING "Additional Arguments to pass to tool.")
set(CODESIGN_CERT_NAME "" CACHE STRING "Name of certificate to sign with.")
set(CODESIGN_CERT_FILE "" CACHE FILEPATH "Path to the certificate to sign with. (Overrides CODESIGN_CERT_NAME)")
set(CODESIGN_CERT_PASS "" CACHE STRING "Password for the certificate.")
set(CODESIGN_TIMESTAMPS ON CACHE BOOL "Timestamp the signed binaries.")

################################################################################
# Functions
################################################################################
function(codesign_initialize_win32)
	# Windows/Cygwin/MSYS
	# - Figure out where the Windows 10 SDKs are.
	# - From here on out, figure out the best match for the SDK version (prefer newer versions!).
	# - Then find signtool in this.
	# Windows Code Signing is done with 'signtool.exe'.

	# ToDo:
	# - Consider CygWin osslsigncode
	# - Consider enabling Win8.1 SDK support

	if(NOT CODESIGN_BIN_SIGNTOOL)
		# Find the root path to installed Windows 10 Kits.
		set(WINDOWS10KITS_REG_KEY "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots")
		set(WINDOWS10KITS_REG_VAL "KitsRoot10")
		set(WINDOWS10KITS_ROOT_DIR)
		if(CMAKE_HOST_SYSTEM_NAME MATCHES "Windows")
			# Note: must be a cache operation in order to read from the registry.
			get_filename_component(WINDOWS10KITS_ROOT_DIR "[${WINDOWS10KITS_REG_KEY};${WINDOWS10KITS_REG_VAL}]" ABSOLUTE)
		else()
			include(CygwinPaths)

			# On Cygwin, CMake's built-in registry query won't work. Use Cygwin utility "regtool" instead.
			execute_process(COMMAND regtool get "\\${WINDOWS10KITS_REG_KEY}\\${WINDOWS10KITS_REG_VAL}"
				OUTPUT_VARIABLE WINDOWS10KITS_ROOT_DIR
				ERROR_QUIET
				OUTPUT_STRIP_TRAILING_WHITESPACE
			)
			if(WINDOWS10KITS_ROOT_DIR)
				convert_windows_path(WINDOWS10KITS_ROOT_DIR)
			endif()
		endif()

		# If we have no path, show an error.
		if(NOT WINDOWS10KITS_ROOT_DIR)
			message(WARNING "CMake CodeSign: Could not find a working Windows 10 SDK, disabling code signing.")
			return()
		endif()

		# List up any found Windows 10 SDK versions.
		file(GLOB WINDOWS10KITS_VERSIONS "${WINDOWS10KITS_ROOT_DIR}/bin/10.*")
		if(CMAKE_VERSION VERSION_LESS "3.18.0")
			list(REVERSE WINDOWS10KITS_VERSIONS)
		else()
			list(SORT WINDOWS10KITS_VERSIONS COMPARE NATURAL CASE INSENSITIVE ORDER DESCENDING)
		endif()

		# Find a fitting 'signtool.exe'.
		foreach(VERSION ${WINDOWS10KITS_VERSIONS})
			message(STATUS "Windows 10 Kit: ${VERSION}")
			find_program(CODESIGN_BIN_SIGNTOOL
				NAMES
					"signtool"
				HINTS
					"${CODESIGN_PATH}"
					"${VERSION}"
				PATHS
					"${CODESIGN_PATH}"
					"${VERSION}"
				PATH_SUFFIXES
					"x64"
					"x86"
			)

			if(CODESIGN_BIN_SIGNTOOL)
				break()
			endif()
		endforeach()
	endif()
endfunction()

function(codesign_initialize)
	# Find the tools by platform.
	if(WIN32)
		codesign_initialize_win32()
	elseif(APPLE)
		codesign_initialize_apple()
	else()
		message(FATAL_ERROR "CMake CodeSign: No supported Platform found.")
	endif()
endfunction()

function(codesign_timestamp_server)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"SHA1;SHA2;SHA256"
		"RETURN"
		""
	)

	set(_list "")
	if(_ARGS_SHA2 OR _ARGS_SHA256)
		list(APPEND _list
			"http://timestamp.digicert.com"
			"http://aatl-timestamp.globalsign.com/tsa/aohfewat2389535fnasgnlg5m23"
#			"https://timestamp.sectigo.com"
			"http://timestamp.entrust.net/TSS/RFC3161sha2TS"
#			"http://tsa.swisssign.net"
			"http://kstamp.keynectis.com/KSign/"
			"http://tsa.quovadisglobal.com/TSS/HttpTspServer"
#			"http://ts.cartaodecidadao.pt/tsa/server"
			"http://tss.accv.es:8318/tsa"
#			"http://tsa.izenpe.com"
			"http://time.certum.pl"
#			"http://zeitstempel.dfn.de"
			"http://psis.catcert.cat/psis/catcert/tsp"
			"http://sha256timestamp.ws.symantec.com/sha256/timestamp"
			"http://rfc3161timestamp.globalsign.com/advanced"
			"http://timestamp.globalsign.com/tsa/r6advanced1"
			"http://timestamp.apple.com/ts01"
#			"http://tsa.baltstamp.lt"
#			"https://freetsa.org/tsr"
#			"https://www.safestamper.com/tsa"
#			"http://tsa.mesign.com"
#			"https://tsa.wotrus.com"
#			"http://tsa.lex-persona.com/tsa"
		)
	else()
		list(APPEND _list
			# ToDo: Do these still exist?
		)
	endif()

	list(LENGTH _list _len)
	if(_len EQUAL 0)
		set(${_ARGS_RETURN} "" PARENT_SCOPE)
		return()
	endif()

	# Retrieve random entry from list.
	string(RANDOM LENGTH 4 ALPHABET 0123456789 number)
	math(EXPR number "(${number} + 0) % ${_len}")  # Remove extra leading 0s.
	list(GET _list ${number} ${_ARGS_RETURN})

	# Propagate to parent.
	set(${_ARGS_RETURN} "${${_ARGS_RETURN}}" PARENT_SCOPE)
endfunction()

function(codesign_win32)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		""
		""
		"TARGETS"
	)

	# ToDo: Timestamping

	if((NOT CODESIGN_CERT_NAME) AND (NOT DEFINED ENV{CODESIGN_CERT_NAME}) AND (NOT CODESIGN_CERT_FILE) AND (NOT DEFINED ENV{CODESIGN_CERT_FILE}))
		message(FATAL_ERROR "CMake CodeSign: One of CODESIGN_CERT_FILE or CODESIGN_CERT_NAME must be defined.")
	endif()

	if(CODESIGN_BIN_SIGNTOOL)
		# This is 'signtool.exe'
		SET(CMD_ARGS "")
		SET(CMD_ARGS_1 "")
		SET(CMD_ARGS_2 "")

		# Parameters: File/Name
		if(CODESIGN_CERT_FILE)
			list(APPEND CMD_ARGS
				/f "${CODESIGN_CERT_FILE}"
			)
		elseif(DEFINED ENV{CODESIGN_CERT_FILE})
			list(APPEND CMD_ARGS
				/f "$ENV{CODESIGN_CERT_FILE}"
			)
		elseif(CODESIGN_CERT_NAME)
			list(APPEND CMD_ARGS
				/n "${CODESIGN_CERT_NAME}"
			)
		elseif(DEFINED ENV{CODESIGN_CERT_NAME})
			list(APPEND CMD_ARGS
				/n "$ENV{CODESIGN_CERT_NAME}"
			)
		endif()

		# Parameters: Password
		if(CODESIGN_CERT_PASS)
			list(APPEND CMD_ARGS
				/p "${CODESIGN_CERT_PASS}"
			)
		elseif(DEFINED ENV{CODESIGN_CERT_PASS})
			list(APPEND CMD_ARGS
				/p "$ENV{CODESIGN_CERT_PASS}"
			)
		endif()

		# Parameters: Timestamping
		if(CODESIGN_TIMESTAMPS)
			codesign_timestamp_server(SHA1 RETURN TIMESTAMP_SHA1)
			if(TIMESTAMP_SHA1)
				list(APPEND CMD_ARGS_1
					/t ${TIMESTAMP_SHA1}
				)
			endif()

			codesign_timestamp_server(SHA2 RETURN TIMESTAMP_SHA2)
			if(TIMESTAMP_SHA2)
				if(NOT TIMESTAMP_SHA1)
					list(APPEND CMD_ARGS_1
						/tr ${TIMESTAMP_SHA2}
					)
				endif()
				list(APPEND CMD_ARGS_2
					/tr ${TIMESTAMP_SHA2}
				)
			endif()
		endif()

		foreach(_target ${_ARGS_TARGETS})
			# Sign SHA-1 (Windows 8 and earlier)
			add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
				COMMAND ${CODESIGN_BIN_SIGNTOOL}
				ARGS sign ${CMD_ARGS} ${CMD_ARGS_1} ${CODESIGN_ARGS} /fd sha1 /td sha1 $<TARGET_FILE:${_target}>
			)

			# Sign SHA-256 (Windows 10 and newer)
			add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
				COMMAND ${CODESIGN_BIN_SIGNTOOL}
				ARGS sign ${CMD_ARGS} ${CMD_ARGS_2} ${CODESIGN_ARGS} /fd sha256 /td sha256 /as $<TARGET_FILE:${_target}>
			)

			message(STATUS "CMake CodeSign: Added post-build step to project '${_target}'.")
		endforeach()
	elseif(CODESIGN_BIN_OSSLSIGNCODE)
		# This is 'osslsigncode' from CygWin
		SET(CMD_ARGS "")
		SET(CMD_ARGS_1 "")
		SET(CMD_ARGS_2 "")
		if((NOT CODESIGN_CERT_FILE) OR (NOT EXISTS "${CODESIGN_CERT_FILE}"))
			message(FATAL_ERROR "CMake CodeSign: 'osslsigncode' is unable to use Windows's certificate store, define CODESIGN_CERT_FILE.")
		endif()

		# Figure out command
		if(CODESIGN_CERT_FILE)
			list(APPEND CMD_ARGS
				-pkcs12 "${CODESIGN_CERT_FILE}"
			)
		elseif(DEFINED ENV{CODESIGN_CERT_FILE})
			list(APPEND CMD_ARGS
				-pkcs12 "$ENV{CODESIGN_CERT_FILE}"
			)
		elseif(CODESIGN_CERT_NAME)
			# Not Supported
		elseif(DEFINED ENV{CODESIGN_CERT_NAME})
			# Not Supported
		endif()

		# Figure out extra arguments
		if(CODESIGN_CERT_PASS)
			list(APPEND CMD_ARGS
				-pass "${CODESIGN_CERT_PASS}"
			)
		elseif(DEFINED ENV{CODESIGN_CERT_PASS})
			list(APPEND CMD_ARGS
				-pass "$ENV{CODESIGN_CERT_PASS}"
			)
		endif()

		# Parameters: Timestamping
		if(CODESIGN_TIMESTAMPS)
			codesign_timestamp_server(SHA1 RETURN TIMESTAMP_SHA1)
			if(TIMESTAMP_SHA1)
				list(APPEND CMD_ARGS_1
					-t ${TIMESTAMP_SHA1}
				)
			endif()

			codesign_timestamp_server(SHA2 RETURN TIMESTAMP_SHA2)
			if(TIMESTAMP_SHA2)
				if(NOT TIMESTAMP_SHA1)
					list(APPEND CMD_ARGS_1
						-ts ${TIMESTAMP_SHA2}
					)
				endif()
				list(APPEND CMD_ARGS_2
					-ts ${TIMESTAMP_SHA2}
				)
			endif()
		endif()


		# Figure out extra arguments
		set(PASS_ARGS "")
		if(CODESIGN_CERT_PASS)
			set(PASS_ARGS "-pass ${CODESIGN_CERT_PASS}")
		elseif(DEFINED ENV{CODESIGN_CERT_PASS})
			set(PASS_ARGS "-pass $ENV{CODESIGN_CERT_PASS}")
		endif()

		foreach(_target ${_ARGS_TARGETS})
			# Sign SHA-1 (Windows 8 and earlier)
			add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
				COMMAND ${CODESIGN_BIN_OSSLSIGNCODE}
				ARGS ${CMD_ARGS} ${CMD_ARGS_1} ${CODESIGN_ARGS} -h sha1 $<TARGET_FILE:${_target}>
			)

			# Sign SHA-256 (Windows 10 and newer)
			add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
				COMMAND ${CODESIGN_BIN_OSSLSIGNCODE}
				ARGS ${CMD_ARGS} ${CMD_ARGS_2} ${CODESIGN_ARGS} -h sha256 -nest $<TARGET_FILE:${_target}>
			)

			message(STATUS "CMake CodeSign: Added post-build step to project '${_target}'.")
		endforeach()
	else()
		message(FATAL_ERROR "CMake CodeSign: No supported Tool found.")
	endif()
endfunction()

function(codesign)
	# Initialize code sign code.
	codesign_initialize()

	if(WIN32)
		codesign_win32(${ARGV})
	elseif(APPLE)
		codesign_apple(${ARGV})
	else()
		codesign_unix(${ARGV})
	endif()
endfunction()
