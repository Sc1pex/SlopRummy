<script lang="ts">
  import { i18n, setLang } from '../lib/i18n.svelte'
</script>

<button class="btn btn-ghost btn-sm" onclick={() => setLang(i18n.lang === 'ro' ? 'en' : 'ro')} aria-label="Language">
  {i18n.lang === 'ro' ? 'EN' : 'RO'}
</button>
