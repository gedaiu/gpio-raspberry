module gpio;

import std.conv;

enum PinDirection
{
	input,
	output
}

version (X86_64)
{
	static bool[50] pinValues;
	static ulong[50] pinChanges;
	static ulong[50] pinUp;
	static ulong[50] pinDown;
	static PinDirection[50] directions;

	class GPIOPin
	{
		int pinNumber;
		PinDirection direction = PinDirection.output;

		static GPIOPin opCall(ubyte pinNumber, PinDirection direction = PinDirection.output)
		{
			auto pin = new GPIOPin;

			pin.pinNumber = pinNumber;
			pin.direction = direction;

			directions[pinNumber] = direction;
			pinChanges[pinNumber] = 0;
			pinUp[pinNumber] = 0;
			pinDown[pinNumber] = 0;

			return pin;
		}

		@property
		{
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

				if(value) {
					pinUp[pinNumber]++;
				} else {
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

	class GPIOPin
	{
		private
		{
			enum exportFile = "/sys/class/gpio/export";
			enum unexportFile = "/sys/class/gpio/unexport";
			PinDirection _direction;

			ubyte pinNumber;

			string pinFolder;
			string directionFile;
			string valueFile;
		}

		static GPIOPin opCall(ubyte pinNumber, PinDirection direction = PinDirection.output)
		{
			auto pin = new GPIOPin(pinNumber);
			pin.direction = direction;

			return pin;
		}

		this(ubyte pinNumber)
		{
			this.pinNumber = pinNumber;

			pinFolder = "/sys/class/gpio/gpio" ~ to!string(pinNumber);
			directionFile = pinFolder ~ "/direction";
			valueFile = pinFolder ~ "/value";

			activate();
		}

		~this()
		{
			deactivate();
		}

		private
		{
			void writeLine(string file, string str)
			{
				File f = File(file, "w+");
				f.writeln(str);
			}

			string readLine(string file)
			{
				File f = File(file, "r");
				string line = strip(f.readln);
				return (line);
			}

			void activate()
			{
				if (!exists(pinFolder))
				{
					writeLine(exportFile, to!string(pinNumber));
				}
			}

			void deactivate()
			{
				if (exists(pinFolder))
				{
					writeLine(unexportFile, to!string(pinNumber));
				}
			}
		}

		@property
		{

			void direction(PinDirection newPinDirection)
			{
				_direction = newPinDirection;
				writeLine(directionFile, newPinDirection == PinDirection.input ? "in" : "out");
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
				writeLine(valueFile, value ? "1" : "0");
			}

			bool value()
			in
			{
				assert(_direction == PinDirection.input,
						"Expected pin " ~ pinNumber.to!string ~ " direction to be input");
			}
			body
			{
				return readLine(valueFile) == "0" ? false : true;
			}
		}
	}
}
