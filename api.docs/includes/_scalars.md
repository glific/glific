# Scalars

### Boolean

The `Boolean` scalar type represents `true` or `false`.

### DateTime

The `DateTime` scalar type represents a date and time in the UTC
timezone. The DateTime appears in a JSON response as an ISO8601 formatted
string, including UTC timezone ("Z"). The parsed date and time string will
be converted to UTC if there is an offset.

### Time

The `Time` scalar type represents a time without microseconds precision. The Time appears in a JSON response as an ISO8601 formatted string.

### Gid

The `gid` scalar appears in JSON as a String. The string appears to
the glific backend as an integer

### ID

The `ID` scalar type represents a unique identifier, often used to
refetch an object or as key for a cache. The ID type appears in a JSON
response as a String; however, it is not intended to be human-readable.
When expected as an input type, any string (such as `"4"`) or integer
(such as `4`) input value will be accepted as an ID.

### Int

The `Int` scalar type represents non-fractional signed whole numeric values.
Int can represent values between `-(2^53 - 1)` and `2^53 - 1` since it is
represented in JSON as double-precision floating point numbers specified
by [IEEE 754](http://en.wikipedia.org/wiki/IEEE_floating_point).

### Json

A generic json type so return the results as json object

### String

The `String` scalar type represents textual data, represented as UTF-8
character sequences. The String type is most often used by GraphQL to
represent free-form human-readable text.
