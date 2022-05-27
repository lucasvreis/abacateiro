<apply template="Default">
  <h1><Title /></h1>
  <div class="post-meta">
    <Tags><span class="post-tag"><Tag /></span> </Tags>
  </div>
  <Sections />
  <Contents />
  <Footnotes />
  <hr />
  <Backlinks>
    <h5>Referências a esta página (<NumberOfBacklinks />):</h5>
    <BacklinkEntries>
      <div class="backlink"
           onclick="window.location.href = '${BacklinkRoute}'">
        <a class="backlink-link"
           href="${BacklinkRoute}">
          <BacklinkTitle />
        </a>
        <BacklinkExcerpt />
      </div>
    </BacklinkEntries>
    <else />
    <i>Nunhuma outra página faz referências a esta página.</i>
  </Backlinks>
  <!-- <details>
       <summary><b>Parsed AST</b></summary>
       <pre>
       <Show />
       </pre>
       </details> -->
</apply>
