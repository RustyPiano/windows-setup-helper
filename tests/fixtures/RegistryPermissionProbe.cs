using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

public static class RegistryPermissionProbe
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CreateRestrictedToken(SafeAccessTokenHandle existing, uint flags,
        uint disabledCount, [In] SidAndAttributes[] disabled, uint deletedCount, IntPtr deleted,
        uint restrictedCount, IntPtr restricted, out SafeAccessTokenHandle token);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int RegOpenKeyEx(IntPtr key, string subkey, uint options,
        uint access, out IntPtr result);

    [DllImport("advapi32.dll")]
    private static extern int RegCloseKey(IntPtr key);

    public static int CheckWriteAccess(string path, bool restricted)
    {
        Func<int> check = () =>
        {
            IntPtr key;
            int result = RegOpenKeyEx(new IntPtr(unchecked((int)0x80000003)), path, 0, 2, out key);
            if (result == 0) RegCloseKey(key);
            return result;
        };
        if (!restricted) return check();

        var administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        byte[] bytes = new byte[administrators.BinaryLength];
        administrators.GetBinaryForm(bytes, 0);
        IntPtr sid = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, sid, bytes.Length);
            using (var identity = WindowsIdentity.GetCurrent())
            {
                SafeAccessTokenHandle token;
                if (!CreateRestrictedToken(identity.AccessToken, 1, 1,
                    new[] { new SidAndAttributes { Sid = sid } }, 0, IntPtr.Zero,
                    0, IntPtr.Zero, out token))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                using (token) return WindowsIdentity.RunImpersonated(token, check);
            }
        }
        finally { Marshal.FreeHGlobal(sid); }
    }
}
