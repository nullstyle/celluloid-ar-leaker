# ActiveRecord Connection Leaker

This script (test.rb) illustrates a repro case that leaks ActiveRecord connections.

A sample run (the "reserved" output lines shows the connection_ids that are still reserved):

You need to bundle to get the modified celluloid and activerecord libraries.
You can change the `$POOLING` flag to run in normal celluloid mode.

```
➜  leaker git:(master) ✗ bundle exec ruby test.rb

initial state:
reserved: [70250595245040]

non_leaker:
reserved: [70250595245040, 70250597191060]
err: NameError
reserved: [70250595245040, 70250597177120]
err: NameError
reserved: [70250595245040, 70250597171820]
err: NameError
reserved: [70250595245040, 70250597155860]
err: NameError
reserved: [70250595245040, 70250597140240]
err: NameError
reserved: [70250595245040]

leaker:
reserved: [70250595245040, 70250597124540]
err: NameError
reserved: [70250595245040, 70250597124540, 70250597205520, 70250597094780]
err: NameError
reserved: [70250595245040, 70250597124540, 70250597205520, 70250597094780, 70250597079300]
err: NameError
err: ActiveRecord::ConnectionTimeoutError
err: ActiveRecord::ConnectionTimeoutError
reserved: [70250595245040, 70250597124540, 70250597205520, 70250597094780, 70250597079300]

finished state:
reserved: [70250595245040, 70250597124540, 70250597205520, 70250597094780, 70250597079300]
➜  leaker git:(master) ✗
```

## Rough Description

When referencing an undefined local variable or calling an undefined method within
a class method defined on an ActiveRecord::Base subclass in the calling context of a
Celluloid::Pool, ActiveRecord connection objects are not properly returned to the
connection pool.

# Notes:

- This behavior only exhibits itself with when in a class method of an AR::Base 
  subclass.  The following _does not trigger_ the leak:  Calling an instance method
  on an AR::Base subclass, calling a class method on a non-AR::Base subclass,
  calling a module method.

- This behavior seems specific to the exception raised when referencing an undefined
  local.  The following _does not trigger_ the leak: Referencing an undefined constant,
  raising a NameError directly, raising any other Exception.

- I was not able to re-produce this behavior using Thread or Fiber directly.
- I did not test for reproduction on any other DB than postgresql.

