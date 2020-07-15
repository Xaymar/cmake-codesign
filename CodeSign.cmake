# Code signing support for CMake
cmake_minimum_required(VERSION 3.8.0)

function(codesign_initialize)

	if(WIN32)
		# Windows/Cygwin/MSYS
		# - Find Windows 10 Kits from registry.
		# - Enumerate all versions and find newest version.
		
		set(WINDOWS10KITS_REG_KEY "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots")
		set(WINDOWS10KITS_REG_VAL "KitsRoot10")
		
		if (CMAKE_SIZEOF_VOID_P EQUAL 8)
			set(arch x64)
		else()
			set(arch x86)
		endif()

		# Find the root path to installed Windows 10 Kits.
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
		
		# Choose the ideal Windows 10 SDK version.
		set(WINDOWS10KITS_PATH)
		if(CMAKE_SYSTEM_VERSION)
			list(FIND WINDOWS10KITS_VERSIONS "${WINDOWS10KITS_ROOT_DIR}/bin/${CMAKE_SYSTEM_VERSION}.0" FOUND_CMAKE_SYSTEM_VERSION)
			if(NOT FOUND_CMAKE_SYSTEM_VERSION EQUAL -1)
				set(WINDOWS10KITS_PATH "${WINDOWS10KITS_ROOT_DIR}/bin/${CMAKE_SYSTEM_VERSION}.0")
			endif()
		endif()
		if(NOT WINDOWS10KITS_PATH)
			list(GET WINDOWS10KITS_VERSIONS 0 WINDOWS10KITS_PATH)
		endif()
		set(WINDOWS10KITS_PATH "${WINDOWS10KITS_PATH}/${arch}")

		if(WINDOWS10KITS_PATH)
			message(STATUS "CMake CodeSign: Found ideal Windows 10 Kits version at '${WINDOWS10KITS_PATH}'")
			set(CODESIGN_TOOL_PATH "${WINDOWS10KITS_PATH}/signtool.exe" PARENT_SCOPE)
		endif()

	else()
		message("CMake CodeSign: Platform not supported.")

	endif()
endfunction()

function(codesign)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		""
		"CERTIFICATE;PASSWORD"
		"TARGETS"
	)

	codesign_initialize()
	if(NOT CODESIGN_TOOL_PATH)
		return()
	endif()

	foreach(_target ${_ARGS_TARGETS})
		if(WIN32)
			add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
				COMMAND ${CODESIGN_TOOL_PATH}
				ARGS sign /p "${_ARGS_PASSWORD}" /f "${_ARGS_CERTIFICATE}" $<TARGET_FILE:${_target}>
			)
			message(STATUS "CMake CodeSign: Added post-build step to project '${_target}'.")
		endif()
	endforeach()

endfunction()


