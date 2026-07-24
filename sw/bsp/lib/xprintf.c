/*------------------------------------------------------------------------/
/  Universal string handler for user console interface
/-------------------------------------------------------------------------/
/
/  Copyright (C) 2011, ChaN, all right reserved.
/
/ * This software is a free software and there is NO WARRANTY.
/ * No restriction on use. You can use, modify and redistribute it for
/   personal, non-profit or commercial products UNDER YOUR RESPONSIBILITY.
/ * Redistributions of source code must retain the above copyright notice.
/
/-------------------------------------------------------------------------*/

#include "../include/xprintf.h"
#include "../include/uart.h"
#include "../include/sys_defs.h"

#include <stdarg.h>


void (*xfunc_out)(unsigned char);	/* Pointer to the output stream */
static char *outptr;

/*----------------------------------------------*/
/* Put a character                              */
/*----------------------------------------------*/

void xputc (char c)
{
	if (_CR_CRLF && c == '\n') xputc('\r');		/* CR -> CRLF */

	if (outptr) {
		*outptr++ = (unsigned char)c;
		return;
	}

	if (xfunc_out) xfunc_out((unsigned char)c);
}


/*----------------------------------------------*/
/* Put a null-terminated string                 */
/*----------------------------------------------*/

void xputs (					/* Put a string to the default device */
	const char* str				/* Pointer to the string */
)
{
	while (*str)
		xputc(*str++);
}

#ifndef XPRINTF_DISABLE_FLOAT
static unsigned int xfloat_next_digit(unsigned long long *frac, unsigned long long denom)
{
	unsigned int digit = 0;
	unsigned int i;
	unsigned long long acc = 0;

	for (i = 0; i < 10; i++) {
		acc += *frac;
		if (acc >= denom) {
			acc -= denom;
			digit++;
		}
	}

	*frac = acc;
	return digit;
}

static void xput_float(double val, unsigned int width, unsigned int precision, unsigned int flags)
{
	char s[16];
	char frac_s[10];
	unsigned int i, digits, pad, neg;
	unsigned long long mant;
	unsigned long long intpart;
	unsigned long long frac;
	unsigned long long frac_mask;
	unsigned int hi, lo;
	unsigned int exp_bits;
	unsigned int round_digit;
	int exp2;

	if (precision > 9) {
		precision = 9;
	}

	union {
		double d;
		unsigned int w[2];
	} cvt;

	cvt.d = val;
	/* RISC-V targets in this tree are little-endian. */
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
	hi = cvt.w[0];
	lo = cvt.w[1];
#else
	hi = cvt.w[1];
	lo = cvt.w[0];
#endif
	neg = hi >> 31;
	exp_bits = (hi >> 20) & 0x7ff;
	mant = ((unsigned long long)(hi & 0xfffff) << 32) | lo;

	if (neg) {
		xputc('-');
	}

	if (exp_bits == 0x7ff) {
		xputs(mant ? "nan" : "inf");
		return;
	}

	if (exp_bits == 0 && mant == 0) {
		intpart = 0;
		for (i = 0; i < precision; i++) {
			frac_s[i] = '0';
		}
		goto print_parts;
	}

	if (exp_bits == 0) {
		exp2 = 1 - 1023 - 52;
	} else {
		mant |= (1ULL << 52);
		exp2 = (int)exp_bits - 1023 - 52;
	}

	if (exp2 >= 0) {
		intpart = mant << exp2;
		for (i = 0; i < precision; i++) {
			frac_s[i] = '0';
		}
	} else {
		unsigned int rshift = (unsigned int)(-exp2);

		if (rshift >= 63) {
			intpart = 0;
			frac = mant;
			for (i = 0; i < precision; i++) {
				frac_s[i] = '0';
			}
		} else {
			intpart = mant >> rshift;
			frac_mask = (1ULL << rshift) - 1ULL;
			frac = mant & frac_mask;
			frac_mask++;

			for (i = 0; i < precision; i++) {
				frac_s[i] = (char)('0' + xfloat_next_digit(&frac, frac_mask));
			}

			round_digit = xfloat_next_digit(&frac, frac_mask);
			if (round_digit >= 5) {
				for (i = precision; i > 0; i--) {
					if (frac_s[i - 1] < '9') {
						frac_s[i - 1]++;
						break;
					}
					frac_s[i - 1] = '0';
				}
				if (i == 0) {
					intpart++;
				}
			}
		}
	}

print_parts:
	i = 0;
	do {
		s[i++] = (char)('0' + (intpart % 10ULL));
		intpart /= 10ULL;
	} while (intpart && i < sizeof(s));

	digits = i + 1 + precision;
	pad = (width > digits) ? (width - digits) : 0;
	while (!(flags & 2) && pad--) {
		xputc((flags & 1) ? '0' : ' ');
	}

	do {
		xputc(s[--i]);
	} while (i);

	xputc('.');
	for (i = 0; i < precision; i++) {
		xputc(frac_s[i]);
	}

	while ((flags & 2) && pad--) {
		xputc(' ');
	}
}
#endif


/*----------------------------------------------*/
/* Formatted string output                      */
/*----------------------------------------------*/
/*  xprintf("%d", 1234);			"1234"
    xprintf("%6d,%3d%%", -200, 5);	"  -200,  5%"
    xprintf("%-6u", 100);			"100   "
    xprintf("%ld", 12345678L);		"12345678"
    xprintf("%04x", 0xA3);			"00a3"
    xprintf("%08LX", 0x123ABC);		"00123ABC"
    xprintf("%016b", 0x550F);		"0101010100001111"
    xprintf("%s", "String");		"String"
    xprintf("%-4s", "abc");			"abc "
    xprintf("%4s", "abc");			" abc"
    xprintf("%c", 'a');				"a"
    xprintf("%f", 10.0);            <xprintf lacks floating point support>
*/

static
void xvprintf (
	const char*	fmt,	/* Pointer to the format string */
	va_list arp			/* Pointer to arguments */
)
{
	unsigned int r, i, j, w, f;
	unsigned long v;
	char s[16], c, d, *p;

	for (;;) {
		c = *fmt++;					/* Get a char */
		if (!c) break;				/* End of format? */
		if (c != '%') {				/* Pass through it if not a % sequense */
			xputc(c); continue;
		}
		f = 0;
		c = *fmt++;					/* Get first char of the sequense */
		if (c == '%') {
			xputc('%');
			continue;
		}
		if (c == '0') {				/* Flag: '0' padded */
			f = 1; c = *fmt++;
		} else {
			if (c == '-') {			/* Flag: left justified */
				f = 2; c = *fmt++;
			}
		}
		for (w = 0; c >= '0' && c <= '9'; c = *fmt++)	/* Minimum width */
			w = w * 10 + c - '0';
		unsigned int precision = 6;
		if (c == '.') {
			c = *fmt++;
			precision = 0;
			while (c >= '0' && c <= '9') {
				precision = precision * 10 + c - '0';
				c = *fmt++;
			}
		}
		if (c == 'l' || c == 'L') {	/* Prefix: Size is long int */
			f |= 4; c = *fmt++;
		}
		if (!c) break;				/* End of format? */
		d = c;
		if (d >= 'a') d -= 0x20;

#ifndef XPRINTF_DISABLE_FLOAT
		if (d == 'F') {
			xput_float(va_arg(arp, double), w, precision, f);
			continue;
		}
#endif

		switch (d) {				/* Type is... */
		case 'S' :					/* String */
			p = va_arg(arp, char*);
			for (j = 0; p[j]; j++) ;
			while (!(f & 2) && j++ < w) xputc(' ');
			xputs(p);
			while (j++ < w) xputc(' ');
			continue;
		case 'C' :					/* Character */
			xputc((char)va_arg(arp, int)); continue;
		case 'B' :					/* Binary */
			r = 2; break;
		case 'O' :					/* Octal */
			r = 8; break;
		case 'D' :					/* Signed decimal */
		case 'U' :					/* Unsigned decimal */
			r = 10; break;
		case 'X' :					/* Hexdecimal */
			r = 16; break;
		default:					/* Unknown type (passthrough) */
			xputc(c); continue;
		}

		/* Get an argument and put it in numeral */
		v = (f & 4) ? va_arg(arp, long) : ((d == 'D') ? (long)va_arg(arp, int) : (long)va_arg(arp, unsigned int));
		if (d == 'D' && (v & 0x80000000)) {
			v = 0 - v;
			f |= 8;
		}
		i = 0;
		do {
			d = (char)(v % r); v /= r;
			if (d > 9) d += (c == 'x') ? 0x27 : 0x07;
			s[i++] = d + '0';
		} while (v && i < sizeof(s));
		if (f & 8) s[i++] = '-';
		j = i; d = (f & 1) ? '0' : ' ';
		while (!(f & 2) && j++ < w) xputc(d);
		do xputc(s[--i]); while(i);
		while (j++ < w) xputc(' ');
	}
}

int xprintf (			/* Put a formatted string to the default device */
	const char*	fmt,	/* Pointer to the format string */
	...					/* Optional arguments */
)
{
	va_list arp;


	va_start(arp, fmt);
	xvprintf(fmt, arp);
	va_end(arp);
	return 0;
}

// UART输出函数
static void uart_putchar(unsigned char c) {
    uart_write((UART_TypeDef *)UART0_BASE, c);
}

// 初始化xprintf重定向到UART
void xprintf_uart_init(void) {
    xdev_out(uart_putchar);
}
