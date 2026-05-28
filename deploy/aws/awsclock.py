"""
Clock-skew-corrected AWS client factory.

This machine's system clock is months ahead of real time, which makes AWS
SigV4 signing fail with SignatureDoesNotMatch (skew > 5 min). The AWS CLI
cannot be fixed on macOS (SIP strips DYLD_INSERT_LIBRARIES, so libfaketime
does not apply to the python launcher). Instead we drive AWS via botocore and
override the timestamp used during request signing to AWS's actual server time.

Usage:
    from awsclock import session, offset
    sts = session().client("sts")
    print(sts.get_caller_identity())

The offset between local clock and AWS server time is computed once from the
sts endpoint Date header and applied to all signing timestamps.
"""
import datetime as _dt
import urllib.request
import urllib.error
import botocore.auth
import boto3

_PROFILE = "slide"
_REGION = "us-east-1"


def _server_now():
    req = urllib.request.Request("https://sts.us-east-1.amazonaws.com", method="HEAD")
    try:
        r = urllib.request.urlopen(req, timeout=10)
        d = r.headers.get("Date")
    except urllib.error.HTTPError as e:
        d = e.headers.get("Date")
    return _dt.datetime.strptime(d, "%a, %d %b %Y %H:%M:%S %Z").replace(
        tzinfo=_dt.timezone.utc
    )


_offset = _server_now() - _dt.datetime.now(_dt.timezone.utc)


def offset():
    return _offset


# Patch the datetime class botocore.auth uses so every signature is stamped
# with corrected (server) time. botocore.auth references the *module* datetime
# and calls datetime.datetime.utcnow(); we subclass to shift utcnow()/now() and
# swap in a shim module exposing that class.
_RealDateTime = _dt.datetime


class _ShiftedDateTime(_RealDateTime):
    @classmethod
    def utcnow(cls):
        return (_RealDateTime.utcnow() + _offset).replace(tzinfo=None)

    @classmethod
    def now(cls, tz=None):
        base = _RealDateTime.now(tz)
        return base + _offset


import types as _types

_shim = _types.ModuleType("datetime")
for _name in dir(_dt):
    setattr(_shim, _name, getattr(_dt, _name))
_shim.datetime = _ShiftedDateTime
botocore.auth.datetime = _shim


def session():
    return boto3.Session(profile_name=_PROFILE, region_name=_REGION)


if __name__ == "__main__":
    print("clock offset (server - local):", _offset)
    sts = session().client("sts")
    print(sts.get_caller_identity())
