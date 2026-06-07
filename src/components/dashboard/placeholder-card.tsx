import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

interface PlaceholderCardProps {
  title: string
  description: string
  action?: React.ReactNode
}

export function PlaceholderCard({ title, description, action }: PlaceholderCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        {action ?? (
          <p className="text-sm text-muted-foreground">
            This section will be available in a future phase.
          </p>
        )}
      </CardContent>
    </Card>
  )
}
