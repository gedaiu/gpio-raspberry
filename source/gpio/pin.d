module gpio.pin;

import std.stdio;
import std.conv;
import std.string;

import core.thread;

alias PinNumber = ubyte;

enum PinDirection
{
	input,
	output
}

enum PinPull : ubyte
{
	off = 0,
	up = 1,
	down = 2
}

interface IGPIOPin {
	void log();

	@property
	{
		void direction(PinDirection newPinDirection, PinPull pull = PinPull.down);
		PinDirection direction();
		void value(bool value);
		bool value();

		long changes();
	}
}

version (X86_64)
{
	static __gshared bool[50] pinValues;
	static __gshared ulong[50] pinChanges;
	static __gshared ulong[50] pinUp;
	static __gshared ulong[50] pinDown;
	static __gshared PinDirection[50] directions;

	void resetPins() {
		foreach(i; 0 .. 50) {
			pinValues[i] = false;
			pinChanges[i] = 0;
			pinUp[i] = 0;
			pinDown[i] = 0;
			directions[i] = PinDirection.output;
		}
	}

	void setDebugValue(const PinNumber number, bool value) {
		pinValues[number] = value;
	};

	bool debugValue(const PinNumber number) {
		return pinValues[number];
	};

	auto stateChanges(const PinNumber number) {
		return pinChanges[number];
	}

	auto stateUpChanges(const PinNumber number) {
		return pinUp[number];
	}

	auto stateDownChanges(const PinNumber number) {
		return pinDown[number];
	}

	class GPIOPin : IGPIOPin
	{
		private
		{
			PinNumber pinNumber;
			bool lastValue;
		}

		static GPIOPin opCall(PinNumber pinNumber, PinDirection direction = PinDirection.output, PinPull pull = PinPull.down)
		{
			auto pin = new GPIOPin;

			pin.pinNumber = pinNumber;

			directions[pinNumber] = direction;
			pinChanges[pinNumber] = 0;
			pinUp[pinNumber] = 0;
			pinDown[pinNumber] = 0;

			return pin;
		}

		void log()
		{
			write(pinValues[pinNumber]);
		}

		@property
		{
			void direction(PinDirection newPinDirection, PinPull pull = PinPull.down)
			{
				directions[pinNumber] = newPinDirection;
			}

			long changes() {
				return pinChanges[pinNumber];
			}

			PinDirection direction()
			{
				return directions[pinNumber];
			}

			void value(bool value)
			in
			{
				assert(direction == PinDirection.output,
						"Expected pin " ~ pinNumber.to!string ~ " direction to be output");
			}
			body
			{
				pinValues[pinNumber] = value;
				pinChanges[pinNumber]++;

				if (value)
				{
					pinUp[pinNumber]++;
				}
				else
				{
					pinDown[pinNumber]++;
				}
			}

			bool value()
			in
			{
				assert(direction == PinDirection.input,
						"Expected pin " ~ pinNumber.to!string ~ " direction to be input");
			}
			body
			{
				return pinValues[pinNumber];
			}
		}
	}
}

version (ARM)
{
	import std.stdio;
	import std.string;
	import std.file;
	import core.sys.posix.sys.mman;
	import core.sys.posix.fcntl;
	import core.sys.posix.unistd;
	import core.stdc.stdio;

	private
	{
		enum BCM2708PeriBase = 0x20000000; // raspberry pi 1
		enum BCM2836PeriBase = 0x3F000000; // raspberry pi 2
		enum BCM2837PeriBase = 0x3F000000; // raspberry pi 3

		immutable uint GPPUD = 0x0094; ///< GPIO Pin Pull-up/down Enable
		immutable uint GPPUDCLK0 = 0x0098; ///< GPIO Pin Pull-up/down Enable Clock 0
		immutable uint GPPUDCLK1 = 0x009c; ///< GPIO Pin Pull-up/down Enable Clock 1

		enum GPIOBase = BCM2837PeriBase + 0x200000; /* GPIO controller */

		enum pageSize = 4 * 1024;
		enum blockSize = 4 * 1024;

		void* gpioMap;
		__gshared uint* gpio;

		void GPIOInput(ubyte pinNumber, PinPull pull)
		{
			*(gpio + ((pinNumber) / 10)) &= ~(7 << (((pinNumber) % 10) * 3));

			pragma(inline, true);
			GPIOPinPull(pinNumber, pull);
			pragma(inline, false);
		}

		void GPIOOutput(ubyte pinNumber, PinPull pull = PinPull.down)
		{
			pragma(inline, true);
			GPIOInput(pinNumber, pull);
			pragma(inline, false);

			*(gpio + ((pinNumber) / 10)) |= (1 << (((pinNumber) % 10) * 3));
		}

		bool GPIOGet(ubyte pinNumber)
		{
			return (*(gpio + 13) & (1 << pinNumber)) == 0 ? false : true;
		}

		void GPIOPull(ubyte pud)
		{
			uint* paddr = gpio + GPPUD / 4;
			*paddr = pud;
			*paddr = pud;
		}

		void GPIOPudClk(ubyte pin, ubyte on)
		{
			uint* paddr = gpio + GPPUDCLK0 / 4 + pin / 32;
			ubyte shift = pin % 32;

			*paddr = (on ? 1 : 0) << shift;
			*paddr = (on ? 1 : 0) << shift;
		}

		void GPIOPinPull(ubyte pin, ubyte pud)
		{
			GPIOPull(pud);
			Thread.sleep(10.usecs);

			GPIOPudClk(pin, 1);
			Thread.sleep(10.usecs);

			GPIOPull(0);
			GPIOPudClk(pin, 0);
		}

		void GPIOSet(ubyte pinNumber, bool value)
		{
			if (value)
			{
				*(gpio + 7) = 1 << pinNumber;
			}
			else
			{
				*(gpio + 10) = 1 << pinNumber;
			}
		}
	}

	shared static this()
	{
		auto fileName = "/dev/mem".toStringz;
		auto mem = open(fileName, O_RDWR | O_SYNC);

		if (mem < 0)
		{
			perror("open\0".ptr);
			throw new Exception("Can't open `/dev/mem`");
		}

		gpioMap = mmap(null, blockSize, PROT_READ | PROT_WRITE, MAP_SHARED, mem, GPIOBase);
		close(mem);

		if (gpioMap == MAP_FAILED)
		{
			perror("mmap\0".ptr);
			throw new Exception("mmap error " ~ (cast(int) gpioMap).to!string ~ "\n");
		}

		gpio = cast(uint*) gpioMap;
	}

	class GPIOPin : IGPIOPin
	{
		private
		{
			PinDirection _direction;

			PinNumber pinNumber;
			ubyte lastValue;
			long _changes = 0;
		}

		static GPIOPin opCall(PinNumber pinNumber, PinDirection direction = PinDirection.output, PinPull pull = PinPull.down)
		{
			auto pin = new GPIOPin(pinNumber);
			pin.direction(direction, pull);

			return pin;
		}

		this(PinNumber pinNumber)
		{
			this.pinNumber = pinNumber;
		}

		void log()
		{
			write(lastValue);
		}

		@property
		{
			long changes() {
				return _changes;
			}

			void direction(PinDirection newPinDirection, PinPull pull = PinPull.down)
			{
				_direction = newPinDirection;

				if (newPinDirection == PinDirection.input)
				{
					GPIOInput(pinNumber, pull);
				}
				else
				{
					GPIOOutput(pinNumber);
				}
			}

			PinDirection direction()
			{
				return _direction;
			}

			void value(bool value)
			in
			{
				assert(_direction == PinDirection.output,
						"Expected pin " ~ pinNumber.to!string ~ " direction to be output");
			}
			body
			{
				lastValue = value;
				_changes++;
				return GPIOSet(pinNumber, value);
			}

			bool value()
			in
			{
				assert(_direction == PinDirection.input,
						"Expected pin " ~ pinNumber.to!string ~ " direction to be input");
			}
			body
			{
				return GPIOGet(pinNumber);
			}
		}
	}
}
