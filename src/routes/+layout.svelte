<script>
	import '../app.css';
	import favicon from '$lib/assets/favicon.svg';
	import { supabase } from '$lib/supabase';
	import { user } from '$lib/auth';
	import { onMount } from 'svelte';

	let { children, data } = $props();

	onMount(() => {
		const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
			user.set(session?.user ?? null);
		});

		user.set(data.user);

		return () => subscription.unsubscribe();
	});
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

{@render children?.()}
