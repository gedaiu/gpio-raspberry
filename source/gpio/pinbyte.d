module gpio.pinbyte;

public import gpio.pin;

import std.array;
import std.algorithm.iteration;

struct GPIOPinByte
{
	private GPIOPin[8] dataPins;

	@disable this();

	this(const ubyte[8] pinList)
	{
		dataPins = pinList.dup.map!(a => GPIOPin(a)).array;
	}

	void setReadDirection()
	{
		foreach (pin; dataPins)
		{
			pin.direction = PinDirection.input;
		}
	}

	void setWriteDirection()
	{
		foreach (pin; dataPins)
		{
			pin.direction = PinDirection.output;
		}
	}

	@property
	{
		void value(ubyte val)
		{
			setWriteDirection;
			immutable ubyte mask = 1;

			foreach (i; 0 .. 8)
			{
				dataPins[i].value = (val & mask) == 1;
				val = val >> 1;
			}
		}

		ubyte value()
		{
			ubyte val = 0;

			setReadDirection;
			immutable ubyte mask = 1;

			foreach (i; 0 .. 8)
			{
				val = cast(ubyte)(val << 1);
				val = val | cast(ubyte)(dataPins[i].value ? 1 : 0);
			}

			return val;
		}
	}
}

@("Set read and write direction")
unittest
{
	auto pinByte = GPIOPinByte([8, 9, 2, 3, 4, 5, 6, 7]);

	pinByte.setReadDirection();

	foreach (pin; pinByte.dataPins)
	{
		assert(pin.direction == PinDirection.input);
	}

	pinByte.setWriteDirection();

	foreach (pin; pinByte.dataPins)
	{
		assert(pin.direction == PinDirection.output);
	}
}

@("Set value")
unittest
{
	auto pinByte = GPIOPinByte([8, 9, 2, 3, 4, 5, 6, 7]);

	pinByte.value = 255;
	foreach (pin; pinByte.dataPins)
	{
		assert(pin.direction == PinDirection.output);
	}

	assert(pinValues[8]);
	assert(pinValues[9]);
	assert(pinValues[2]);
	assert(pinValues[3]);
	assert(pinValues[4]);
	assert(pinValues[5]);
	assert(pinValues[6]);
	assert(pinValues[7]);

	pinByte.value = 0;
	assert(!pinValues[8]);
	assert(!pinValues[9]);
	assert(!pinValues[2]);
	assert(!pinValues[3]);
	assert(!pinValues[4]);
	assert(!pinValues[5]);
	assert(!pinValues[6]);
	assert(!pinValues[7]);

	pinByte.value = 90;
	assert(!pinValues[8]);
	assert(pinValues[9]);
	assert(!pinValues[2]);
	assert(pinValues[3]);
	assert(pinValues[4]);
	assert(!pinValues[5]);
	assert(pinValues[6]);
	assert(!pinValues[7]);
}

@("Get value")
unittest
{
	auto pinByte = GPIOPinByte([8, 9, 2, 3, 4, 5, 6, 7]);

	pinValues[8] = true;
	pinValues[9] = true;
	pinValues[2] = true;
	pinValues[3] = true;
	pinValues[4] = true;
	pinValues[5] = true;
	pinValues[6] = true;
	pinValues[7] = true;

	assert(pinByte.value == 255);

	foreach (pin; pinByte.dataPins)
	{
		assert(pin.direction == PinDirection.input);
	}

	pinValues[8] = false;
	pinValues[9] = false;
	pinValues[2] = false;
	pinValues[3] = false;
	pinValues[4] = false;
	pinValues[5] = false;
	pinValues[6] = false;
	pinValues[7] = false;
	assert(pinByte.value == 0);

	pinValues[8] = false;
	pinValues[9] = true;
	pinValues[2] = false;
	pinValues[3] = true;
	pinValues[4] = true;
	pinValues[5] = false;
	pinValues[6] = true;
	pinValues[7] = false;

	assert(pinByte.value == 90);
}
