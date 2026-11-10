// CLI adapter for the external revorb converter; no third-party source is embedded.
// Build with -Ibuild/reference after fetching its licensed revorb.cpp there.
#include "revorb.cpp"

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    std::ifstream input(argv[1], std::ios::binary);
    std::stringstream output(std::ios::in | std::ios::out | std::ios::binary);
    if (!input || !revorb::revorb(input, output)) return 1;
    std::ofstream result(argv[2], std::ios::binary);
    result << output.rdbuf();
    return result ? 0 : 1;
}
