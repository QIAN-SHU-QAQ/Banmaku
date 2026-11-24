#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <filesystem>
#include <memory>

#include "flutter_window.h"
#include "utils.h"

namespace {
std::filesystem::path GetProgramDirectory() {
  std::wstring file_name(32768, L'\0');
  const DWORD length = ::GetModuleFileNameW(
      nullptr, file_name.data(), static_cast<DWORD>(file_name.size()));
  if (length == 0 || length >= file_name.size()) {
    return {};
  }
  file_name.resize(length);
  return std::filesystem::path(file_name).parent_path();
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool is_player =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--player") != command_line_arguments.end();

  const auto program_dir = GetProgramDirectory();
  using Handle = std::unique_ptr<void, decltype(&::CloseHandle)>;
  Handle portable_running(nullptr, ::CloseHandle);
  Handle profile_lock(nullptr, ::CloseHandle);
  const DWORD marker = ::GetFileAttributesW((program_dir / L"portable.ini").c_str());
  if (!program_dir.empty() && marker != INVALID_FILE_ATTRIBUTES &&
      !(marker & FILE_ATTRIBUTE_DIRECTORY)) {
    // Setup checks this mutex before replacing files used by either process.
    portable_running.reset(
        ::CreateMutexW(nullptr, FALSE, L"Local\\BanmakuPortableRunning"));
    if (!is_player) {
      const auto data = program_dir.parent_path() / L"UserData";
      std::error_code error;
      std::filesystem::create_directories(data, error);
      const HANDLE lock = ::CreateFileW(
          (data / L"profile.lock").c_str(), GENERIC_WRITE, 0, nullptr,
          OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (lock == INVALID_HANDLE_VALUE) {
        ::MessageBoxW(nullptr,
                      L"\u6b64\u4fbf\u643a\u76ee\u5f55\u5df2\u5728\u8fd0\u884c\uff0c\u6216 UserData \u6587\u4ef6\u5939\u4e0d\u53ef\u5199\u3002",
                      L"Banmaku", MB_OK | MB_ICONERROR);
        return EXIT_FAILURE;
      }
      profile_lock.reset(lock);
    }
  }

  // Initialize COM before creating the engine and registering plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  flutter::DartProject project((program_dir / L"data").wstring());

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, is_player);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Banmaku", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
