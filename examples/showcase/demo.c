// ChromaFlow showcase: inspect individual tokens; do not treat this as an application.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEMO_SCALE(value) ((value) * 2)
#if defined(__STDC__)
#define DEMO_STANDARD 1
#endif

/**
 * @brief Doxygen comment, documentation tags and a documented declaration.
 */
typedef struct DemoRecord {
	int mutable_field;
	const int readonly_field; // expected clangd modifier: readonly / property
	const char *label;
} DemoRecord;

typedef int (*BinaryOperation)(int left, int right);

enum DemoKind {
	DEMO_ZERO,
	DEMO_ONE = 1,
	DEMO_HEX = 0x2A,
};

// expected clangd modifier: declaration / variable
extern int declared_global;

// expected clangd modifier: definition / variable
int declared_global = 7;

// expected clangd modifier: static / variable
static int file_static = 11;

// expected clangd modifier: readonly / variable
const int readonly_global = 13;

// expected clangd modifier: deprecated / function
__attribute__((deprecated("showcase only")))
int legacy_increment(int value);

int legacy_increment(int value) {
	return value + 1;
}

static int add(int left, int right) {
	return left + right;
}

// modifier comparison: readonly / parameter and readonly / property
static int inspect_readonly(const int readonly_parameter, DemoRecord record) {
	return readonly_parameter + record.readonly_field;
}

// expected clangd modifier: definition / function
int main(int argc, char **argv) {
	int local_variable = DEMO_SCALE(readonly_global);
	static int function_static = 3; // expected clangd modifier: static / variable

	DemoRecord record = { .mutable_field = 4, .readonly_field = 5, .label = "record" };
	BinaryOperation operation = add;
	int (*function_pointer)(int, int) = add;

	// LSP-dependent: defaultLibrary / function
	printf("%s %d\n", record.label, operation(local_variable, function_static));
	// LSP-dependent: defaultLibrary / function
	size_t label_size = strlen(record.label);
	char character = 'C';
	double decimal = 3.14159;
	double scientific = 6.02e23;
	double hexadecimal_float = 0x1.fp3;

	// expected clangd modifier: deprecated / function
	local_variable += legacy_increment(record.mutable_field);
	local_variable += inspect_readonly(readonly_global, record);
	local_variable = function_pointer(local_variable, DEMO_ONE);

	if (local_variable > 0 && character != '\0') {
		for (int index = 0; index < 3; ++index) {
			local_variable += index ? 1 : -1;
		}
	}

	// LSP-dependent: defaultLibrary / function
	void *allocated = malloc(label_size + 1);
	if (allocated != NULL) {
		free(allocated); // LSP-dependent: defaultLibrary / function
	}

	return (int)(decimal + scientific * 0 + hexadecimal_float * 0) + argv[0][0] * 0;
}
