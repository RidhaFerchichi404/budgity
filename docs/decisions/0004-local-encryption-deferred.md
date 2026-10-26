# 0004 Local database encryption deferred to P1

**Status:** accepted

**Context:** SQLite files are not encrypted. SQLCipher adds native build complexity on both platforms.

**Decision:** The MVP ships plain SQLite in the per-user app-support directory, with the session token in OS secure storage. P1 adds SQLCipher with a key in Android Keystore / Windows DPAPI.

**Consequences:** Someone with access to the unlocked device or the user profile can read the DB. Documented in security.md.
