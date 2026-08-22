import { signOut } from "@/lib/auth/actions";
import { Button } from "@/components/ui/button";

export function SignOutButton({
  variant = "outline",
}: {
  variant?: React.ComponentProps<typeof Button>["variant"];
}) {
  return (
    <form action={signOut}>
      <Button type="submit" variant={variant}>
        Sign out
      </Button>
    </form>
  );
}
