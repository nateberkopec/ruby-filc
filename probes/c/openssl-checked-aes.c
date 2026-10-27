#define OPENSSL_SUPPRESS_DEPRECATED
#include <openssl/aes.h>
#include <stdfil.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const unsigned char short_input[8] = {0};
static unsigned char short_output[8];
static const unsigned char readonly_output[16] = {0};

int main(int argc, char **argv)
{
    const unsigned char key_bytes[16] = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
    };
    const unsigned char input[16] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
    };
    const unsigned char expected[16] = {
        0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30,
        0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a
    };
    unsigned char output[16], recovered[16];
    AES_KEY key, inverse;
    assert(argc == 2);
    assert(zlength(short_input) == 8 && zlength(short_output) == 8);
    assert(AES_set_encrypt_key(key_bytes, 128, &key) == 0);
    if (!strcmp(argv[1], "valid")) {
        AES_encrypt(input, output, &key);
        assert(!memcmp(output, expected, sizeof(output)));
        assert(AES_set_decrypt_key(key_bytes, 128, &inverse) == 0);
        AES_decrypt(output, recovered, &inverse);
        assert(!memcmp(recovered, input, sizeof(input)));
        puts("AES-128 known-answer and decrypt checks passed");
        return 0;
    }
    if (!strcmp(argv[1], "key")) AES_set_encrypt_key(short_input, 128, &key);
    else if (!strcmp(argv[1], "input")) AES_encrypt(short_input, output, &key);
    else if (!strcmp(argv[1], "output")) AES_encrypt(input, short_output, &key);
    else if (!strcmp(argv[1], "rounds")) {
        key.rounds = 0;
        AES_encrypt(input, output, &key);
    }
    else if (!strcmp(argv[1], "alias")) AES_encrypt(input, (unsigned char *)&key, &key);
    else if (!strcmp(argv[1], "readonly")) AES_encrypt(input, (unsigned char *)readonly_output, &key);
    else {
        fputs("unknown test case\n", stderr);
        return 2;
    }
    fputs("invalid AES call was not rejected\n", stderr);
    return 1;
}
