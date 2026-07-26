# Customer account settings and password recovery

## What is implemented

- Signed-in customers open **Account → Account settings** to edit their name and phone number.
- Appearance supports **System**, **Light**, and **Dark**. The choice is stored on the device and applied at startup.
- Signed-in customers can change their password from Account settings.
- Signed-out customers select **Forgot password?** on the sign-in screen.
- Administrators see ordinary customer accounts under **Manage → Users**. Agents and administrators are excluded from that list.

## Forgot-password flow

1. The customer enters their email on the sign-in screen and selects **Forgot password?**.
2. Supabase sends its password-recovery email.
3. The email link redirects to `kodimali://reset-password`.
4. Android opens KODIMALI and the app presents the new-password screen.
5. Supabase validates the recovery session, then the app calls `auth.updateUser` to save the new password.

The response intentionally says to check email even when an account cannot be identified. This avoids exposing which addresses are registered.

## Required Supabase dashboard configuration

In **Authentication → URL Configuration**, add this redirect URL:

```text
kodimali://reset-password
```

Keep the production website URL as the primary Site URL. Customize the recovery email under **Authentication → Email Templates → Reset Password** if needed, but retain Supabase's generated confirmation URL.

For production Android App Links, a future HTTPS recovery page may redirect into the app. The custom `kodimali://` scheme is already registered in the Android manifest and works directly from supported mail clients.

## Database migration

`20260726143000_admin_customer_users.sql` adds `get_admin_customer_users`. It is a security-definer function that:

- requires the caller to have the admin role;
- returns customer profiles in pages of at most 100;
- excludes accounts that also have agent or admin roles;
- grants execution only to authenticated users, with authorization rechecked inside the function.

## Security and support notes

- Never ask a user for their existing password, email code, or recovery link.
- Passwords require at least eight characters in the client; Supabase remains the source of truth for password policy.
- Changing a password requires a valid signed-in or recovery session.
- Admins can inspect customer identity/profile information but cannot view passwords.
- If a recovery email does not open the app, verify the redirect allow-list, Android installation, and that the email client allows custom-scheme links.
