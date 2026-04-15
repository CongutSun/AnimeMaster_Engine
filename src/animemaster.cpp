#include "animemaster.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

namespace {

namespace fs = std::filesystem;

thread_local std::string g_parse_result;
thread_local std::string g_scan_result;

std::string Trim(std::string value) {
    const auto not_space = [](unsigned char ch) { return !std::isspace(ch); };
    value.erase(
        value.begin(),
        std::find_if(value.begin(), value.end(), not_space)
    );
    value.erase(
        std::find_if(value.rbegin(), value.rend(), not_space).base(),
        value.end()
    );
    return value;
}

std::string ToUpperAscii(std::string value) {
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](unsigned char ch) { return static_cast<char>(std::toupper(ch)); }
    );
    return value;
}

std::string ToLowerAscii(std::string value) {
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); }
    );
    return value;
}

bool StartsWithCaseInsensitive(const std::string& value, const std::string& prefix) {
    if (value.size() < prefix.size()) {
        return false;
    }

    for (size_t i = 0; i < prefix.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(value[i])) !=
            std::tolower(static_cast<unsigned char>(prefix[i]))) {
            return false;
        }
    }
    return true;
}

bool IsHexHash(const std::string& value) {
    if (value.size() != 40) {
        return false;
    }

    return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
        return std::isxdigit(ch) != 0;
    });
}

bool IsBase32Hash(const std::string& value) {
    if (value.size() != 32) {
        return false;
    }

    return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
        const unsigned char upper = static_cast<unsigned char>(std::toupper(ch));
        return (upper >= 'A' && upper <= 'Z') || (upper >= '2' && upper <= '7');
    });
}

int Base32Value(char ch) {
    const unsigned char upper = static_cast<unsigned char>(std::toupper(static_cast<unsigned char>(ch)));
    if (upper >= 'A' && upper <= 'Z') {
        return upper - 'A';
    }
    if (upper >= '2' && upper <= '7') {
        return upper - '2' + 26;
    }
    return -1;
}

std::string Base32ToHex(const std::string& input) {
    std::string bits;
    bits.reserve(input.size() * 5);

    for (char ch : input) {
        const int value = Base32Value(ch);
        if (value < 0) {
            return {};
        }
        for (int bit = 4; bit >= 0; --bit) {
            bits.push_back(((value >> bit) & 1) ? '1' : '0');
        }
    }

    std::string hex;
    hex.reserve(bits.size() / 4);
    for (size_t i = 0; i + 3 < bits.size(); i += 4) {
        int chunk = 0;
        for (size_t j = 0; j < 4; ++j) {
            chunk = (chunk << 1) | (bits[i + j] - '0');
        }
        hex.push_back(static_cast<char>(chunk < 10 ? ('0' + chunk) : ('A' + chunk - 10)));
    }

    return hex;
}

std::string JsonEscape(const std::string& value) {
    std::ostringstream out;
    for (unsigned char ch : value) {
        switch (ch) {
            case '\\':
                out << "\\\\";
                break;
            case '"':
                out << "\\\"";
                break;
            case '\b':
                out << "\\b";
                break;
            case '\f':
                out << "\\f";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                if (ch < 0x20) {
                    constexpr char hex[] = "0123456789ABCDEF";
                    out << "\\u00" << hex[(ch >> 4) & 0x0F] << hex[ch & 0x0F];
                } else {
                    out << static_cast<char>(ch);
                }
                break;
        }
    }
    return out.str();
}

std::string UrlDecode(const std::string& value) {
    std::string decoded;
    decoded.reserve(value.size());

    for (size_t i = 0; i < value.size(); ++i) {
        const char ch = value[i];
        if (ch == '%' && i + 2 < value.size()) {
            const std::string hex = value.substr(i + 1, 2);
            char* end = nullptr;
            const long number = std::strtol(hex.c_str(), &end, 16);
            if (end != nullptr && *end == '\0') {
                decoded.push_back(static_cast<char>(number));
                i += 2;
                continue;
            }
        }

        decoded.push_back(ch == '+' ? ' ' : ch);
    }

    return decoded;
}

std::string UrlEncode(const std::string& value) {
    constexpr char hex[] = "0123456789ABCDEF";
    std::string encoded;
    encoded.reserve(value.size() * 3);

    for (unsigned char ch : value) {
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
            (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' ||
            ch == '.' || ch == '~') {
            encoded.push_back(static_cast<char>(ch));
        } else if (ch == ' ') {
            encoded.push_back('+');
        } else {
            encoded.push_back('%');
            encoded.push_back(hex[(ch >> 4) & 0x0F]);
            encoded.push_back(hex[ch & 0x0F]);
        }
    }

    return encoded;
}

bool IsVideoFile(const fs::path& path) {
    const std::string extension = ToLowerAscii(path.extension().string());
    static const std::vector<std::string> video_extensions = {
        ".mp4", ".mkv", ".avi", ".flv", ".rmvb", ".ts", ".m2ts", ".wmv", ".webm", ".m4v"
    };

    return std::find(video_extensions.begin(), video_extensions.end(), extension) !=
           video_extensions.end();
}

std::string BuildErrorJson(const std::string& message) {
    return std::string("{\"success\":false,\"infoHash\":\"\",\"error\":\"") +
           JsonEscape(message) + "\"}";
}

std::string BuildScanErrorJson(const std::string& path, const std::string& message) {
    return std::string("{\"success\":false,\"path\":\"") + JsonEscape(path) +
           "\",\"error\":\"" + JsonEscape(message) + "\",\"entries\":[]}";
}

}  // namespace

extern "C" {

FFI_PLUGIN_EXPORT bool InitializeEngineCore() {
    return true;
}

FFI_PLUGIN_EXPORT const char* GetEngineVersion() {
    return "AnimeMaster Engine v1.1.0 (Native parser/scanner)";
}

FFI_PLUGIN_EXPORT const char* ParseMagnetLink(const char* magnetUri) {
    const std::string input = Trim(magnetUri == nullptr ? "" : magnetUri);
    if (input.empty()) {
        g_parse_result = BuildErrorJson("Empty magnet source.");
        return g_parse_result.c_str();
    }

    std::string info_hash;
    std::string display_name;
    std::vector<std::string> trackers;
    std::string source_type = "unknown";
    std::string hash_encoding = "unknown";

    if (IsHexHash(input)) {
        info_hash = ToUpperAscii(input);
        source_type = "raw_hash";
        hash_encoding = "hex";
    } else if (IsBase32Hash(input)) {
        info_hash = Base32ToHex(input);
        source_type = "raw_hash";
        hash_encoding = "base32";
    } else if (StartsWithCaseInsensitive(input, "magnet:?")) {
        source_type = "magnet";
        const size_t query_start = input.find('?');
        const std::string query = query_start == std::string::npos ? "" : input.substr(query_start + 1);

        size_t cursor = 0;
        while (cursor <= query.size()) {
            const size_t next = query.find('&', cursor);
            const std::string part = query.substr(cursor, next == std::string::npos ? std::string::npos : next - cursor);
            const size_t equals = part.find('=');
            const std::string raw_key = equals == std::string::npos ? part : part.substr(0, equals);
            const std::string raw_value = equals == std::string::npos ? "" : part.substr(equals + 1);
            const std::string key = ToLowerAscii(UrlDecode(raw_key));
            const std::string value = UrlDecode(raw_value);

            if (key == "xt" && StartsWithCaseInsensitive(value, "urn:btih:")) {
                const std::string candidate = value.substr(9);
                if (IsHexHash(candidate)) {
                    info_hash = ToUpperAscii(candidate);
                    hash_encoding = "hex";
                } else if (IsBase32Hash(candidate)) {
                    info_hash = Base32ToHex(candidate);
                    hash_encoding = "base32";
                }
            } else if (key == "dn" && display_name.empty()) {
                display_name = value;
            } else if (key == "tr" && !value.empty()) {
                trackers.push_back(value);
            }

            if (next == std::string::npos) {
                break;
            }
            cursor = next + 1;
        }
    }

    if (!IsHexHash(info_hash)) {
        g_parse_result = BuildErrorJson("Unable to extract a valid BitTorrent info hash.");
        return g_parse_result.c_str();
    }

    std::ostringstream normalized_magnet;
    normalized_magnet << "magnet:?xt=urn:btih:" << info_hash;
    if (!display_name.empty()) {
        normalized_magnet << "&dn=" << UrlEncode(display_name);
    }
    for (const auto& tracker : trackers) {
        normalized_magnet << "&tr=" << UrlEncode(tracker);
    }

    std::ostringstream json;
    json << "{"
         << "\"success\":true,"
         << "\"sourceType\":\"" << JsonEscape(source_type) << "\","
         << "\"hashEncoding\":\"" << JsonEscape(hash_encoding) << "\","
         << "\"infoHash\":\"" << JsonEscape(info_hash) << "\","
         << "\"displayName\":\"" << JsonEscape(display_name) << "\","
         << "\"trackerCount\":" << trackers.size() << ","
         << "\"normalizedMagnet\":\"" << JsonEscape(normalized_magnet.str()) << "\","
         << "\"trackers\":[";

    for (size_t i = 0; i < trackers.size(); ++i) {
        if (i > 0) {
            json << ",";
        }
        json << "\"" << JsonEscape(trackers[i]) << "\"";
    }
    json << "]}";

    g_parse_result = json.str();
    return g_parse_result.c_str();
}

FFI_PLUGIN_EXPORT const char* ScanLocalDirectory(const char* path) {
    const std::string input_path = Trim(path == nullptr ? "" : path);
    if (input_path.empty()) {
        g_scan_result = BuildScanErrorJson("", "Empty scan path.");
        return g_scan_result.c_str();
    }

    std::error_code ec;
    const fs::path root = fs::u8path(input_path);
    if (!fs::exists(root, ec) || ec) {
        g_scan_result = BuildScanErrorJson(input_path, "Directory does not exist.");
        return g_scan_result.c_str();
    }

    if (!fs::is_directory(root, ec) || ec) {
        g_scan_result = BuildScanErrorJson(input_path, "Scan path is not a directory.");
        return g_scan_result.c_str();
    }

    constexpr size_t kMaxEntries = 500;
    size_t count = 0;
    std::ostringstream json;
    json << "{"
         << "\"success\":true,"
         << "\"path\":\"" << JsonEscape(root.u8string()) << "\","
         << "\"entries\":[";

    fs::recursive_directory_iterator iterator(
        root,
        fs::directory_options::skip_permission_denied,
        ec
    );
    fs::recursive_directory_iterator end;

    bool first = true;
    for (; iterator != end && count < kMaxEntries; iterator.increment(ec)) {
        if (ec) {
            ec.clear();
            continue;
        }

        const fs::directory_entry& entry = *iterator;
        const bool is_directory = entry.is_directory(ec);
        if (ec) {
            ec.clear();
            continue;
        }

        const bool is_regular_file = entry.is_regular_file(ec);
        if (ec) {
            ec.clear();
            continue;
        }

        if (!is_directory && !is_regular_file) {
            continue;
        }

        const fs::path entry_path = entry.path();
        const fs::path relative_path = fs::relative(entry_path, root, ec);
        if (ec) {
            ec.clear();
        }

        uintmax_t size = 0;
        if (is_regular_file) {
            size = entry.file_size(ec);
            if (ec) {
                size = 0;
                ec.clear();
            }
        }

        long long modified_at_epoch_ms = 0;
        entry.last_write_time(ec);
        if (ec) {
            ec.clear();
        }

        if (!first) {
            json << ",";
        }
        first = false;
        ++count;

        json << "{"
             << "\"name\":\"" << JsonEscape(entry_path.filename().u8string()) << "\","
             << "\"path\":\"" << JsonEscape(entry_path.u8string()) << "\","
             << "\"relativePath\":\"" << JsonEscape(relative_path.empty() ? entry_path.filename().u8string() : relative_path.u8string()) << "\","
             << "\"isDirectory\":" << (is_directory ? "true" : "false") << ","
             << "\"isVideo\":" << (!is_directory && IsVideoFile(entry_path) ? "true" : "false") << ","
             << "\"size\":" << size << ","
             << "\"modifiedAtEpochMs\":" << modified_at_epoch_ms
             << "}";
    }

    json << "],\"truncated\":" << (count >= kMaxEntries ? "true" : "false") << "}";
    g_scan_result = json.str();
    return g_scan_result.c_str();
}

}  // extern "C"
