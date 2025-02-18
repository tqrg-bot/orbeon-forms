<!--
  Copyright (C) 2011 Orbeon, Inc.

  This program is free software; you can redistribute it and/or modify it under the terms of the
  GNU Lesser General Public License as published by the Free Software Foundation; either version
  2.1 of the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU Lesser General Public License for more details.

  The full text of the license is available at http://www.gnu.org/copyleft/lesser.html
  -->
<xsl:stylesheet
        version="2.0"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:xf="http://www.w3.org/2002/xforms"
        xmlns:xxf="http://orbeon.org/oxf/xml/xforms"
        xmlns:fr="http://orbeon.org/oxf/xml/form-runner"
        xmlns:xh="http://www.w3.org/1999/xhtml"
        xmlns:xi="http://www.w3.org/2001/XInclude"
        xmlns:xxi="http://orbeon.org/oxf/xml/xinclude"
        xmlns:ev="http://www.w3.org/2001/xml-events"
        xmlns:xbl="http://www.w3.org/ns/xbl"
        xmlns:frf="java:org.orbeon.oxf.fr.FormRunner"
        xmlns:p="http://www.orbeon.com/oxf/pipeline"
        xmlns:map="http://www.w3.org/2005/xpath-functions/map"
        xmlns:array="http://www.w3.org/2005/xpath-functions/array"
        xmlns:d="DAV:">

    <xsl:variable name="view"           select="(/xh:html/xh:body/fr:view)[1]"       as="element(fr:view)?"/>
    <xsl:variable name="fluid"          select="$view/@fluid = 'true'"/>
    <xsl:variable name="body"           select="($view/fr:body, $view)[1]"           as="element()?"/>
    <xsl:variable name="custom-buttons" select="$view/fr:buttons"                    as="element()*"/>

    <!-- Template for the default layout of a form -->
    <xsl:variable name="default-page-template" as="element(*)*">
        <fr:navbar/>

        <fr:description/>

        <!-- Error summary (if at top) -->
        <xsl:if test="$error-summary-top">
            <fr:error-summary position="top"/>
        </xsl:if>

        <fr:row>
            <fr:toc/>
        </fr:row>
        <fr:row>
            <fr:body/>
        </fr:row>
        <fr:row>
            <fr:captcha/>
        </fr:row>

        <!-- Error summary (if at bottom) -->
        <!-- If we configuration tells us the bottom error summary should not be shown, still include it but hide it with 'display: none'.
             This is necessary because the persistence model relies on the error summary to know if the data is valid. -->
        <xh:div>
            <xsl:if test="not($error-summary-bottom)">
                <xsl:attribute name="class">xforms-hidden</xsl:attribute>
            </xsl:if>
            <fr:error-summary position="bottom"/>
        </xh:div>

        <fr:row>
            <fr:messages/>
        </fr:row>
        <fr:row>
            <fr:buttons-bar/>
        </fr:row>
        <fr:row>
            <fr:version/>
        </fr:row>
    </xsl:variable>

    <xsl:template match="fr:row">
        <xh:div class="row{if ($fluid) then '-fluid' else ''}">
            <xh:div class="span12">
                <xsl:apply-templates select="@* | node()"/>
            </xh:div>
        </xh:div>
    </xsl:template>

    <xsl:template match="fr:body">

        <xf:var name="persistence-instance"    value="xxf:instance('fr-persistence-instance')"/>
        <xf:var name="lease-enabled"           value="$persistence-instance/lease-enabled = 'true'"/>
        <xf:var name="lease-state-elem"        value="$persistence-instance/lease-state"/>
        <xf:var name="show-form-data"          value="not($lease-enabled) or  $lease-state-elem = 'current-user'"/>

        <xf:group
            ref="if ($lease-enabled) then . else ()"
            class="alert alert-info fr-lease"
            xxf:element="div"
        >
            <xh:i class="fa fa-lock" aria-hidden="true"/>

            <fr:alert-dialog id="fr-lease-renew-dialog">
                <fr:label>Renew lease?</fr:label>
                <fr:message>Your lease is about to expire. Would you like to renew it now?</fr:message>
                <fr:negative-choice/>
                <fr:positive-choice>
                    <xf:send event="DOMActivate" submission="fr-acquire-lease-submission"/>
                </fr:positive-choice>
            </fr:alert-dialog>

            <xh:div class="fr-lease-message">
                <xf:switch caseref="$lease-state-elem">
                    <xf:case value="'current-user'">
                        <xh:div>
                            <xf:output value="$fr-resources/detail/lease/current-user-left"/>
                            <fr:countdown
                                ref="$persistence-instance/lease-end-time"
                                alert-threshold-ref="$persistence-instance/lease-alert-threshold">
                                <xf:action
                                    event="fr-countdown-ended"
                                    if="$lease-state-elem = 'current-user'">
                                    <xf:dispatch
                                        target="fr-lease-renew-dialog"
                                        name="fr-hide"/>
                                    <xf:setvalue
                                        ref="$lease-state-elem"
                                        value="'relinquished'"/>
                                </xf:action>
                                <xf:action
                                    event="fr-countdown-alert"
                                    if="$lease-state-elem = 'current-user'">
                                    <xf:dispatch
                                        target="fr-lease-renew-dialog"
                                        name="fr-show"/>
                                </xf:action>
                            </fr:countdown>
                            <xf:output value="$fr-resources/detail/lease/current-user-right"/>
                        </xh:div>
                    </xf:case>
                    <xf:case value="'relinquished'">
                        <xf:output value="$fr-resources/detail/lease/relinquished"/>
                    </xf:case>
                    <xf:case value="'other-user'">
                        <xf:output value="
                            xxf:format-message(
                                $fr-resources/detail/lease/other-user,
                                xxf:instance('fr-lockinfo-response')/d:owner/fr:username/string()
                            )
                        "/>
                    </xf:case>
                </xf:switch>
            </xh:div>

            <xh:div class="fr-lease-buttons">
                <xf:switch caseref="
                        if ($lease-state-elem = 'current-user')
                        then 'has-lease'
                        else 'does-not-have-lease'">
                    <xf:case value="'has-lease'">
                        <xf:trigger class="xforms-trigger-appearance-modal">
                            <xf:label ref="$fr-resources/detail/lease/relinquish"/>
                            <xf:action event="DOMActivate" type="xpath">
                                xxf:instance('fr-form-instance')/fr:run-process-by-name('oxf.fr.detail.process', 'relinquish-lease')
                            </xf:action>
                        </xf:trigger>
                        <xf:trigger class="xforms-trigger-appearance-modal">
                            <xf:label ref="$fr-resources/detail/lease/renew"/>
                            <xf:action event="DOMActivate">
                                <xf:send submission="fr-acquire-lease-submission"/>
                            </xf:action>
                        </xf:trigger>
                    </xf:case>
                    <xf:case value="'does-not-have-lease'">
                        <xf:trigger class="xforms-trigger-appearance-modal">
                            <xf:label ref="$fr-resources/detail/lease/try-acquire"/>
                            <xf:action event="DOMActivate">
                                <xf:setvalue ref="$persistence-instance/lease-load-document">true</xf:setvalue>
                                <xf:send submission="fr-acquire-lease-submission"/>
                            </xf:action>
                        </xf:trigger>
                    </xf:case>
                </xf:switch>
            </xh:div>
        </xf:group>

        <!--
            Form content. Set context on form instance and define this group as `#fr-form-group` as observers will refer to it.
            NOTE: Use `fr-view-component` whenever possible instead since Orbeon Forms 2017.1.
        -->
        <xf:group
            id="fr-form-group"
            class="{
                'fr-body',
                'fr-border'[$is-detail],
                concat('fr-validation-mode-', $validation-mode)
            }"
            model="fr-form-model"
            ref="
                if ($show-form-data) then
                    instance('fr-form-instance')
                else
                    ()"
            xxf:validation-mode="{$validation-mode}"
        >
            <xsl:if test="$is-full-update">
                <xsl:attribute name="xxf:update">full</xsl:attribute>
            </xsl:if>

            <!-- FIXME: `<a name>` is deprecated in favor of `id`. -->
            <xh:a name="fr-form"/>
            <xsl:choose>
                <xsl:when test="not($mode = ('edit', 'new', 'test')) or $is-form-builder or $view-appearance = 'full'">
                    <xf:group id="fr-view-component" class="fr-view-appearance-full">

                        <xsl:apply-templates select="if ($body) then $body/(node() except fr:buttons) else node()"/>

                        <!-- Keep markup even in `view` mode for form caching. -->
                        <xxf:setvisited
                            event="fr-visit-all fr-show-relevant-errors"
                            target="#observer"

                            control="fr-view-component"
                            visited="true"
                            recurse="true"/>
                    </xf:group>
                </xsl:when>
                <xsl:otherwise>
                    <!-- Insert appropriate XBL component -->
                    <!-- NOTE: Once we support XBL matching on @appearance, use instead
                         <fr:view appearance="{$view-appearance}">. -->
                    <xsl:element name="fr:{$view-appearance}">
                        <xsl:attribute name="id"              select="'fr-view-component'"/>
                        <xsl:attribute name="class"           select="concat('fr-view-appearance-', $view-appearance)"/>

                        <xsl:attribute name="app"             select="$app"/>
                        <xsl:attribute name="form"            select="$form"/>

                        <xsl:for-each select="$wizard-mode[1]">
                            <!--
                                We'd prefer `mode` to match the term used in the documentation, or maybe
                                `forward-validation-mode`. But `validate` is how the property was named.
                            -->
                            <xsl:attribute name="validate" select="."/>
                        </xsl:for-each>

                        <xsl:for-each select="$wizard-subsections-nav[1]">
                            <xsl:attribute name="subsections-nav" select="."/>
                        </xsl:for-each>

                        <xsl:for-each select="$wizard-subsections-toc[1]">
                            <xsl:attribute name="subsections-toc" select="."/>
                        </xsl:for-each>

                        <!--
                            This is the `incremental|explicit` Form Runner validation mode, which is passed to the wizard but
                            is also used separately from the wizard. Here too the name should be clearer.
                        -->
                        <xsl:attribute name="validation-mode" select="$validation-mode"/>

                        <xsl:apply-templates select="if ($body) then $body/(node() except fr:buttons) else node()"/>
                        <!-- Optional inner buttons -->
                        <xsl:if test="exists($inner-buttons)">
                            <xsl:call-template name="fr-buttons-bar">
                                <xsl:with-param name="buttons-property"  select="'oxf.fr.detail.buttons.inner'" tunnel="yes"/>
                                <xsl:with-param name="highlight-primary" select="true()"                        tunnel="yes"/>
                                <xsl:with-param name="inverse"           select="false()"                       tunnel="yes"/>
                            </xsl:call-template>
                        </xsl:if>
                    </xsl:element>
                </xsl:otherwise>
            </xsl:choose>
            <!--<fr:xforms-inspector/>-->
        </xf:group>
    </xsl:template>

    <!-- Main entry point -->
    <xsl:template match="xh:body">
        <xsl:copy>
            <!-- .orbeon is here to scope all Orbeon CSS rules -->
            <xsl:attribute
                name="class"
                select="
                    string-join(
                        (
                            'orbeon',
                            'xforms-disable-alert-as-tooltip',
                            @class
                        ),
                        ' '
                    )"/>
            <xsl:apply-templates select="@* except @class"/>
            <xf:group model="fr-form-model" id="fr-view" class="container{if ($fluid) then '-fluid' else ''} fr-view {{concat('fr-mode-', $fr-mode)}}" xxf:element="div">
                <xh:div class="popover-container-right"/>
                <xh:div class="popover-container-left"/>
                <xsl:apply-templates select="if ($is-detail and not($is-form-builder)) then $default-page-template else node()"/>
                <xsl:call-template name="fr-hidden-controls"/>
                <xsl:call-template name="fr-dialogs"/>
            </xf:group>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="fr:navbar" name="fr-navbar">
        <xf:group
                xxf:element="div"
                model="fr-form-model"
                ref=".[not(xxf:property(string-join(('oxf.fr.detail.hide-header', fr:app-name(), fr:form-name()), '.')))]"
                class="navbar navbar-inverse">
            <xh:div class="navbar-inner">
                <xh:div class="container">
                    <xsl:variable name="default-objects" as="element()+">
                        <fr:goto-content/>
                        <!-- These are typically to the left -->
                        <fr:logo/>
                        <fr:title/>
                        <!-- These are typically to the right -->
                        <fr:language-selector/>
                        <fr:status-icons/>
                        <fr:user-nav/>
                    </xsl:variable>

                    <xsl:apply-templates select="$default-objects"/>
                </xh:div>
            </xh:div>
        </xf:group>
    </xsl:template>

    <xsl:template match="fr:hidden-controls" name="fr-hidden-controls">
        <xh:span class="xforms-hidden">

            <!-- Communicate to the client whether the data is safe -->
            <xf:var
                name="fr-data-safe"
                model="fr-persistence-model"
                ref="instance('fr-persistence-instance')/data-safe"
                value="data(.)">
                <xf:action
                    type="javascript"
                    event="xforms-enabled xforms-value-changed"
                    if="xxf:property(string-join(('oxf.fr.detail.warn-when-data-unsafe', fr:app-name(), fr:form-name()), '.'))">
                    <xf:param name="safe" value="."/>
                    <xf:body>ORBEON.fr.private.API.setDataStatus(safe == "true")</xf:body>
                </xf:action>
            </xf:var>

            <!-- Expose document id to JavaScript -->
            <xf:output id="fr-parameters-instance-document" ref="fr:document-id()" class="xforms-hidden"/>

            <!-- When the mode changes to "edit" after a save from /new, attempt to change the URL -->
            <!-- NOTE: Keep `xxf:instance()`, see https://github.com/orbeon/orbeon-forms/issues/2872 -->
            <xf:var name="mode-for-save" value="xxf:instance('fr-parameters-instance')/mode/string()">
                <!-- If URI is /new (it should be), change it to /edit/id -->
                <!-- If browser supporting the HTML5 history API (http://goo.gl/Ootqu) -->
                <xf:action type="javascript" ev:event="xforms-value-changed" if="$mode-for-save = 'edit'">
                    <![CDATA[
                        if (history && history.replaceState) {
                            var NewSuffix = '/new';
                            var endsWithNew = location.pathname.indexOf(NewSuffix, location.pathname.length - NewSuffix.length) != -1;
                            if (endsWithNew) {
                                var documentId = ORBEON.xforms.Document.getValue("fr-parameters-instance-document");
                                var editSuffix = "edit/" +
                                    documentId +
                                    location.search +   // E.g. ?form-version=42
                                    location.hash;      // For now not used by Form Runner, but it is safer to keep it
                                history.replaceState(null, "", editSuffix);
                            }
                        }
                    ]]>
                </xf:action>
            </xf:var>

            <!-- This is a HACK for Form Builder only: place non-relevant instances of all toolbox controls so that
                 xxf:dynamic will have all the JavaScript and CSS resources available on the client.
                 See: https://github.com/orbeon/orbeon-forms/issues/31 -->
            <xsl:if test="$is-form-builder and $is-detail" xmlns:p="http://www.orbeon.com/oxf/pipeline" xmlns:fb="http://orbeon.org/oxf/xml/form-builder">

                <xsl:variable name="property-names"
                              select="p:properties-start-with('oxf.fb.toolbox.group')" as="xs:string*" />
                <xsl:variable name="resources-names"
                              select="distinct-values(for $n in $property-names return p:split(p:property($n)))" as="xs:string*"/>

                <xsl:variable name="resources"
                              select="for $uri in $resources-names return doc($uri)" as="document-node()*"/>

                <xsl:if test="$resources">
                    <!-- Non-relevant group -->
                    <xf:group ref="()">
                        <xsl:apply-templates select="$resources/*/xbl:binding/fb:metadata/(fb:template | fb:templates/fb:view)/*" mode="filter-fb-template"/>
                        <!-- So that the xxbl:global for repeated sections is included -->
                        <fr:repeater/>
                    </xf:group>
                </xsl:if>
            </xsl:if>
        </xh:span>
    </xsl:template>

    <xsl:template match="fr:captcha" name="fr-captcha">
        <xsl:if test="$has-captcha">
            <xf:group id="fr-captcha-group" model="fr-persistence-model" ref=".[frf:showCaptcha()]" class="fr-captcha">
                <xf:var name="captcha" value="instance('fr-persistence-instance')/captcha"/>
                <!-- Success: remember the captcha passed, which also influences validity -->
                <xf:action ev:event="fr-verify-done">
                    <xf:setvalue ref="$captcha">true</xf:setvalue>
                    <xf:revalidate model="fr-persistence-model"/>
                    <xf:refresh/>
                </xf:action>
                <!-- Failure: load another challenge -->
                <xf:action event="fr-verify-error">
                    <xf:dispatch
                        if="event('fr-error-code') != 'empty'"
                        targetid="captcha"
                        name="fr-reload"/>
                </xf:action>
                <!-- Captcha component -->
                <xsl:element
                    namespace="{$captcha-uri-name[1]}"
                    name     ="{$captcha-uri-name[2]}"
                >
                    <xsl:attribute name="id">captcha</xsl:attribute>
                    <xsl:attribute name="ref">$captcha</xsl:attribute>
                    <xf:label model="fr-form-model" ref="$fr-resources/detail/labels/captcha-label"/>
                    <xf:alert model="fr-form-model" ref="$fr-resources/detail/labels/captcha-alert"/>
                </xsl:element>
            </xf:group>
        </xsl:if>
    </xsl:template>

    <!-- Remove id elements on Form Builder templates -->
    <xsl:template match="@id | @bind" mode="filter-fb-template"/>
    <xsl:template match="@ref[not(normalize-space())] | @nodeset[not(normalize-space())]" mode="filter-fb-template">
        <xsl:attribute name="{name()}" select="'()'"/>
    </xsl:template>

    <xsl:template match="fr:title" name="fr-title">
        <!-- Q: Why do we need @ref here? -->
        <xh:h1><xf:output value="{if (exists(@ref)) then @ref else '$title'}"/></xh:h1>
    </xsl:template>

    <!-- Description in chosen language or first one if not found -->
    <xsl:template match="fr:description" name="fr-description">
        <xh:div class="row{if ($fluid) then '-fluid' else ''}">
            <xh:div class="span12">

                <xf:var
                    name="description"
                    value="
                        (
                            { if (@paths) then concat(@paths, ', ') else '' }
                            xxf:instance('fr-form-metadata')/description[@xml:lang = xxf:instance('fr-language-instance')],
                            xxf:instance('fr-form-metadata')/description
                        )[normalize-space()][1]"/>

                <xf:group xxf:element="div" ref=".[xxf:non-blank($description)]" class="alert fr-form-description">
                    <!-- Don't allow closing as that removes the markup and the XForms engine might attempt to update the nested
                         xf:output, which will cause an error. -->
                    <xf:output value="$description"/>
                </xf:group>
            </xh:div>
        </xh:div>
    </xsl:template>

    <xsl:template match="fr:logo">
        <xsl:if test="not($hide-logo) and exists($default-logo-uri)">
            <xh:div>
                <xh:img src="{$default-logo-uri}" alt=""/>
            </xh:div>
        </xsl:if>
    </xsl:template>

    <xsl:template match="fr:language-selector">
        <!-- Switch language -->
        <xf:group xxf:element="div" model="fr-form-model" ref=".[not($fr-mode = ('view', 'pdf', 'email'))]" class="fr-language-choice">
            <!-- Put default language first, then other languages -->
            <xf:var
                name="available-languages"
                model="fr-resources-model"
                value="frf:getFormLangSelection($app, $form, $fr-selector-resources/resource/@xml:lang/string())"/>

            <!-- Don't display language selector if there is only one language -->
            <!-- NOTE: Resolve model here, as for now model within XBL component won't resolve -->
            <!-- FIXME: This logic is duplicated in dialog-itemset.xbl -->
            <xf:group
                id="fr-language-selector"
                model="fr-resources-model"
                ref="
                    .[
                        count($available-languages) gt 1 and
                        xxf:is-blank(xxf:get-request-header('orbeon-liferay-language'))
                    ]">
                <xf:select1 ref="$fr-selector-lang" appearance="bootstrap" id="fr-language-selector-select">
                    <xf:itemset ref="$available-languages">
                        <xf:label ref="(xxf:instance('fr-languages-instance')/language[@code = context()]/@native-name, context())[1]"/>
                        <xf:value ref="context()"/>
                    </xf:itemset>
                </xf:select1>
            </xf:group>
        </xf:group>
    </xsl:template>

    <xsl:template match="fr:goto-content">
        <xf:group model="fr-form-model" class="xforms-hidden">
            <!-- Group to scope variables -->
            <xf:group appearance="xxf:internal" model="fr-error-summary-model">
                <!-- Link to form content or to errors if any -->
                <xh:a class="fr-goto-content" href="#{{if (counts/@error gt 0) then 'fr-errors' else 'fr-form'}}">
                    <xf:output model="fr-form-model" value="$fr-resources/summary/labels/goto-content"/>
                </xh:a>
            </xf:group>
        </xf:group>
    </xsl:template>

    <xsl:template match="fr:user-nav">
        <xf:group class="fr-user-nav" ref=".[xxf:property('oxf.fr.authentication.user-menu.enable')]">
            <xh:ul class="nav pull-right">
                <xh:li class="dropdown">
                    <xh:a id="menu-button" href="#" class="dropdown-toggle" data-toggle="dropdown">
                        <xh:i class="fa fa-user"/>
                    </xh:a>
                    <xh:ul class="dropdown-menu" role="menu" aria-labelledBy="menu-button">
                        <xf:var name="signed-in"     value="exists(xxf:username())"/>
                        <xf:var name="for-signed-in" value="if (    $signed-in ) then '' else 'xforms-hidden'"/>
                        <xf:var name="for-anonymous" value="if (not($signed-in)) then '' else 'xforms-hidden'"/>
                        <xh:li role="presentation" class="disabled {{$for-signed-in}}">
                            <xh:a role="menuitem" href="#">
                                Signed in as <xh:b><xf:output value="xxf:username()"/></xh:b>
                            </xh:a>
                        </xh:li>
                        <xh:li role="presentation" class="divider {{$for-signed-in}}"/>
                        <xh:li role="presentation" class="{{$for-signed-in}}">
                            <xf:trigger role="menuitem" appearance="minimal">
                                <xf:label>Sign out</xf:label>
                            </xf:trigger>
                        </xh:li>
                        <xh:li role="presentation" class="{{$for-anonymous}}">
                            <xh:a role="menuitem" href="{{xxf:property('oxf.fr.authentication.user-menu.uri.signin')}}">
                                Sign in
                            </xh:a>
                        </xh:li>
                        <xh:li role="presentation" class="{{$for-anonymous}}">
                            <xh:a role="menuitem" href="{{xxf:property('oxf.fr.authentication.user-menu.uri.signup')}}">
                                Sign up
                            </xh:a>
                        </xh:li>
                    </xh:ul>
                </xh:li>
            </xh:ul>
        </xf:group>
    </xsl:template>

    <xsl:template match="fr:version">
        <xsl:if test="$version">
            <fr:row>
                <xh:div class="fr-orbeon-version"><xsl:value-of select="$version"/></xh:div>
            </fr:row>
        </xsl:if>
    </xsl:template>

    <!-- Content handled separately -->
    <xsl:template match="fr:dialogs"/>

    <xsl:template name="fr-dialogs">
        <!-- Copy custom dialogs under fr:dialogs only (other dialogs will be left in place) -->
        <xsl:apply-templates select=".//fr:dialogs//xxf:dialog"/>

        <!-- Misc standard dialogs -->
        <xi:include href="oxf:/apps/fr/includes/clear-dialog.xhtml"            xxi:omit-xml-base="true"/>
        <xi:include href="oxf:/apps/fr/includes/draft-singleton-dialogs.xhtml" xxi:omit-xml-base="true"/>
        <xi:include href="oxf:/apps/fr/includes/submission-dialog.xhtml"       xxi:omit-xml-base="true"/>
        <xi:include href="oxf:/apps/fr/includes/validation-dialog.xhtml"       xxi:omit-xml-base="true"/>

        <!-- Include dialogs from property -->
        <xsl:variable
            name="custom-dialogs"
            select="p:split(p:property(string-join(('oxf.fr.detail.dialogs.custom', $app, $form), '.')))"/>
        <xsl:for-each select="$custom-dialogs">
            <xsl:copy-of select="doc(.)"/>
        </xsl:for-each>

        <!-- Error dialog -->
        <fr:alert-dialog id="fr-error-dialog" close="true">
            <fr:label ref="$fr-resources/detail/messages/error-dialog-title"/>
            <fr:neutral-choice/>
        </fr:alert-dialog>

        <!-- Generic confirmation dialog (message must be passed dynamically) -->
        <fr:alert-dialog id="fr-confirmation-dialog" close="true">
            <fr:label ref="$fr-resources/detail/messages/confirmation-dialog-title"/>
            <fr:negative-choice>
                <xf:action event="DOMActivate" type="xpath">
                    fr:run-process('oxf.fr.detail.process', 'abort')
                </xf:action>
            </fr:negative-choice>
            <fr:positive-choice>
                <xf:action event="DOMActivate" type="xpath">
                    fr:run-process('oxf.fr.detail.process', 'resume')
                </xf:action>
            </fr:positive-choice>
        </fr:alert-dialog>

        <!-- Listen for upload events -->
        <xf:action
            ev:event="xxforms-upload-error"
            ev:observer="fr-view-component"
            ev:defaultAction="cancel"
            xxf:phantom="true">
            <xf:action type="xpath">
                frf:errorMessage(
                    if (event('error-type') = 'size-error') then
                        xxf:format-message(
                            xxf:r(
                                'detail.messages.upload-error-size',
                                'fr-fr-resources'
                            ),
                            (
                                event('permitted'),
                                event('actual')
                            )
                        )
                    else if (event('error-type') = 'mediatype-error') then
                        xxf:format-message(
                            xxf:r(
                                'detail.messages.upload-error-mediatype',
                                'fr-fr-resources'
                            ),
                            (
                                (: NOTE: As of 2017-11-09 this is not used by the message. :)
                                event('permitted'),
                                event('actual')
                            )
                        )
                    else if (event('error-type') = 'file-scan-error') then
                        xxf:format-message(
                            xxf:r(
                                'detail.messages.upload-error-file-scan',
                                'fr-fr-resources'
                            ),
                            (
                                event('message')
                            )
                        )
                    else
                        xxf:r(
                            concat('detail.messages.', substring-after(event('xxf:type'), 'xxforms-')),
                            'fr-fr-resources'
                        )
                )
            </xf:action>
        </xf:action>

        <xf:action
            ev:event="xxforms-upload-done"
            ev:observer="fr-view-component"
            ev:defaultAction="cancel"
            xxf:phantom="true"
            type="xpath">
            frf:successMessage(
                xxf:r(
                    concat('detail.messages.', substring-after(event('xxf:type'), 'xxforms-')),
                    'fr-fr-resources'
                )
            )
        </xf:action>

    </xsl:template>

    <!-- Error summary UI -->
    <xsl:template match="fr:error-summary" name="fr-error-summary">
        <xsl:param name="position" select="@position" as="xs:string"/>

        <!-- NOTE: We used to only handle events coming from controls bound to "fr-form-instance" instance, but this
             doesn't work with "section templates". We now use the observer mechanism of fr:error-summary -->

        <!-- For form builder we disable the error summary and say that the form is always valid -->
        <xsl:if test="not($is-form-builder)">
            <fr:row>
                <fr:error-summary
                    id="error-summary-control-{$position}"
                    observer="fr-view-component fr-captcha-group"
                    model="fr-error-summary-model"
                    alerts-count-ref="counts/@alert"
                    errors-count-ref="counts/@error"
                    warnings-count-ref="counts/@warning"
                    infos-count-ref="counts/@info"
                    visible-alerts-count-ref="visible-counts/@alert"
                    visible-errors-count-ref="visible-counts/@error"
                    visible-warnings-count-ref="visible-counts/@warning"
                    visible-infos-count-ref="visible-counts/@info"
                    valid-ref="valid"
                >
                    <fr:label>
                        <!-- If there are e.g. some errors AND warnings, the formatter will display a generic word such as "message" -->
                        <xf:output
                            value="
                                xxf:format-message(
                                    $fr-resources/errors/summary-title,
                                    (
                                        xxf:instance('fr-error-summary-instance')/visible-counts/(
                                            if (count((@error, @warning, @info)[. gt 0]) gt 1) then
                                                3
                                            else if (@error gt 0) then
                                                0
                                            else if (@warning gt 0) then
                                                1
                                            else if (@info gt 0) then
                                                2
                                            else
                                                4
                                        ),
                                        xxf:instance('fr-error-summary-instance')/visible-counts/xs:integer(@alert)
                                    )
                                )"/>
                    </fr:label>
                    <xsl:if test="$position = 'bottom'">
                        <fr:header/>
                    </xsl:if>
                    <xsl:if test="$position = 'top'">
                        <fr:footer/>
                    </xsl:if>
                </fr:error-summary>
            </fr:row>
        </xsl:if>

    </xsl:template>

    <!-- Optional standard explanation message for view mode -->
    <xsl:template name="fr-explanation">
        <xf:group
                xxf:element="div"
                model="fr-form-model"
                ref=".[$fr-mode = 'view' and xxf:property(string-join(('oxf.fr.detail.view.show-explanation', fr:app-name(), fr:form-name()), '.')) = true()]"
                class="fr-explanation">
            <xf:output value="$fr-resources/detail/view/explanation"/>
        </xf:group>
    </xsl:template>

    <xsl:template match="fr:status-icons" name="fr-status-icons">
        <!-- Status icons for detail page -->

        <xf:group
            model="fr-form-model"
            ref=".[not($fr-mode = ('summary', 'home'))]"
            class="fr-status-icons">

            <xf:group model="fr-error-summary-model" ref=".[visible-counts/@alert gt 0]">
                <!-- Form has error or warning messages -->
                <xf:repeat ref="visible-counts/(@error, @warning, @info)[. gt 0]">
                    <xh:span class="badge badge-{{if (name() = 'error') then 'important' else if (name() = 'warning') then 'warning' else 'info'}}">
                        <xf:output value="."/>
                    </xh:span>
                </xf:repeat>
            </xf:group>
            <xf:group model="fr-error-summary-model" ref=".[visible-counts/@alert = 0]" class="fr-validity-icon">
                <!-- Form has no error or warning messages -->
                <xf:group model="fr-form-model"><xh:i class="fa fa-check fa-fw" title="{{$fr-resources/errors/none}}"/></xf:group>
            </xf:group>
            <xf:group model="fr-persistence-model" ref="instance('fr-persistence-instance')[data-status = 'dirty']" class="fr-data-icon">
                <!-- Data is dirty -->
                <xf:group model="fr-form-model"><xh:i class="fa fa-hdd-o fa-fw" title="{{$fr-resources/errors/unsaved}}"/></xf:group>
            </xf:group>
        </xf:group>
    </xsl:template>

    <!-- Success messages -->
    <xsl:template match="fr:messages" name="fr-messages">
        <xf:switch class="fr-messages" model="fr-persistence-model" ref=".[instance('fr-persistence-instance')/message != '']">
            <xf:case id="fr-message-none">
                <xh:span/>
            </xf:case>
            <xf:case id="fr-message-success">
                <xf:output value="instance('fr-persistence-instance')/message" class="fr-message-success alert alert-success"/>
            </xf:case>
        </xf:switch>
    </xsl:template>

    <xsl:template match="fr:buttons-bar" name="fr-buttons-bar">

        <xsl:param name="buttons-property"  tunnel="yes" as="xs:string*"  select="()"/>
        <xsl:param name="highlight-primary" tunnel="yes" as="xs:boolean?" select="()"/>
        <xsl:param name="inverse"           tunnel="yes" as="xs:boolean?" select="()"/>

        <!-- Nothing below must statically depend on the mode -->
        <xsl:choose>
            <xsl:when test="exists($custom-buttons)">
                <xh:span class="fr-buttons">
                    <xsl:apply-templates select="$custom-buttons/node()"/>
                </xh:span>
            </xsl:when>
            <xsl:when test="not($hide-buttons-bar)">
                <xf:group model="fr-form-model" class="fr-buttons">

                    <xf:var name="buttons-property-override"  value="'{$buttons-property}'"/>
                    <xf:var name="highlight-primary-override" value="'{$highlight-primary}'"/>
                    <xf:var name="inverse-override"           value="'{$inverse}'"/>

                    <xf:var
                        name="highlight-primary"
                        value="
                            if ($highlight-primary-override = '') then
                                $fr-mode != 'test'
                            else
                                xs:boolean($highlight-primary-override)"
                    />

                    <xf:var
                        name="inverse"
                        value="
                            if ($inverse-override = '') then
                                $fr-mode  = 'test'
                            else
                                xs:boolean($inverse-override)"/>

                    <!-- Message shown next to the buttons (empty by default) -->
                    <xh:span class="fr-buttons-message">
                        <xf:output mediatype="text/html" ref="$fr-resources/detail/messages/buttons-message"/>
                    </xh:span>

                    <xf:var
                        xmlns:saxon="http://saxon.sf.net/"
                        name="names-and-refs-if-relevant"
                        value="
                            let $buttons-property :=
                                    if (xxf:non-blank($buttons-property-override)) then
                                        $buttons-property-override
                                    else if ($fr-mode = 'view') then
                                        'oxf.fr.detail.buttons.view'
                                    else
                                        'oxf.fr.detail.buttons',
                                $buttons-names :=
                                    if (xxf:is-blank($buttons-property-override) and $fr-mode = ('pdf', 'email')) then
                                        ()
                                    else if (xxf:is-blank($buttons-property-override) and $fr-mode = 'test') then
                                        (('wizard-prev', 'wizard-next')[fr:is-wizard-body-shown()], 'validate')
                                    else
                                        xxf:split(xxf:property(string-join(($buttons-property, fr:app-name(), fr:form-name()), '.'))),
                                $is-inner :=
                                    starts-with($buttons-property-override, 'oxf.fr.detail.buttons.inner')
                            return
                                for $button-name in $buttons-names
                                return
                                    let $visible-expression :=
                                            xxf:property(
                                                string-join(
                                                    ('oxf.fr.detail.button', $button-name, 'visible', fr:app-name(), fr:form-name()),
                                                    '.'
                                                )
                                            ),
                                        $enabled-expression :=
                                            xxf:property(
                                                string-join(
                                                    ('oxf.fr.detail.button', $button-name, 'enabled', fr:app-name(), fr:form-name()),
                                                    '.'
                                                )
                                            ),
                                        $visible-or-empty :=
                                            if (xxf:non-blank($visible-expression)) then
                                                boolean(xxf:instance('fr-form-instance')/saxon:evaluate($visible-expression))
                                            else
                                                (),
                                        $enabled-or-empty :=
                                            if (xxf:non-blank($enabled-expression)) then
                                                boolean(xxf:instance('fr-form-instance')/saxon:evaluate($enabled-expression))
                                            else
                                                ()
                                    return
                                        for $ref in
                                            if (exists($visible-or-empty) or exists($enabled-or-empty)) then
                                                (
                                                    if (exists($enabled-or-empty) and not($enabled-or-empty)) then
                                                        ''
                                                    else
                                                        xxf:instance('fr-triggers-instance')/other
                                                )[
                                                    empty($visible-or-empty) or $visible-or-empty
                                                ]
                                            else if ($is-inner and $button-name = ('save-final', 'submit', 'send', 'review', 'pdf', 'tiff', 'email')) then
                                                xxf:binding('fr-wizard-submit-hide')
                                            else
                                                xxf:instance('fr-triggers-instance')/*[name() = (
                                                    if ($button-name = 'summary') then
                                                        'can-access-summary'
                                                    else if ($button-name = 'pdf') then
                                                        'pdf'
                                                    else if ($button-name = 'tiff') then
                                                        'tiff'
                                                    else
                                                        'other'
                                                )]
                                        return
                                            ($button-name, $ref)[xxf:relevant($ref)]
                        "/>

                    <xf:repeat ref="$names-and-refs-if-relevant[position() mod 2 = 1]">
                        <xf:var name="position"    value="position()"/>
                        <xf:var name="button-name" value="."/>
                        <xf:var name="ref"         value="$names-and-refs-if-relevant[$position * 2]"/>
                        <xf:var name="primary"     value="$highlight-primary and position() = last()"/>

                        <xf:var
                            name="class"
                            value="
                                concat(
                                    'xforms-trigger-appearance-xxforms-',
                                     if ($primary) then
                                        'primary'
                                     else if ($inverse and position() = last()) then
                                        'inverse'
                                     else
                                        'default'
                                )
                        "/>

                        <!-- Because @appearance is static, use a CSS class instead for primary/inverse. This requires
                             changes to form-runner-bootstrap-override.less, which is not the best solution. Ideally,
                             we could find a dynamic way to set that class on the nested <button> so that standard
                             Bootstrap rules apply. -->
                        <fr:process-button
                            name="{{$button-name}}"
                            ref="$ref"
                            class="{{$class}}"/>
                    </xf:repeat>

                </xf:group>
            </xsl:when>
            <xsl:otherwise/>
        </xsl:choose>
    </xsl:template>

    <!-- TOC: Top-level -->
    <xsl:template match="fr:toc" name="fr-toc">
        <!-- This is statically built in XSLT instead of using XForms -->
        <xsl:if test="$has-toc and $is-detail and not($is-form-builder) and count($body//fr:section) ge $min-toc">
            <xh:div class="fr-toc well sidebar-nav">
                <xh:ul class="nav nav-list">
                    <xh:li class="nav-header"><xf:output ref="$fr-resources/summary/titles/toc"/></xh:li>
                    <xsl:apply-templates select="$body" mode="fr-toc-sections"/>
                </xh:ul>
            </xh:div>
        </xsl:if>
    </xsl:template>

    <!-- TOC: Swallow unneeded nodes -->
    <xsl:template match="text()" mode="fr-toc-sections"/>

    <xsl:template match="*" mode="fr-toc-sections">
        <xsl:apply-templates mode="fr-toc-sections"/>
    </xsl:template>

    <!-- TOC: handle section -->
    <xsl:template match="fr:section" mode="fr-toc-sections">
        <xh:li xxf:control="xf:group">
            <!-- Propagate binding so that entry for section disappears if the section is non-relevant -->
            <xsl:copy-of select="@model | @context | @bind | @ref"/>
            <!-- Clicking sets the focus -->
            <xf:trigger appearance="minimal">
                <xf:label value="xxf:label('{@id}')"/>
                <xf:setfocus
                    event="DOMActivate"
                    control="{@id}"
                    includes="{{frf:xpathFormRunnerStringProperty('oxf.fr.detail.focus.includes')}}"
                    excludes="{{frf:xpathFormRunnerStringProperty('oxf.fr.detail.focus.excludes')}}"/>
            </xf:trigger>
            <!-- Sub-sections if any -->
            <xsl:if test="exists(fr:section)">
                <xh:ol>
                    <xsl:apply-templates mode="fr-toc-sections"/>
                </xh:ol>
            </xsl:if>
        </xh:li>
    </xsl:template>

    <!-- Add a default xf:alert for those fields which don't have one. Only do this within grids and dialogs. -->
    <!-- Q: Do we really need this? -->
    <xsl:template
        match="
            xh:body//fr:grid//xf:*[local-name() = ('input', 'textarea', 'select', 'select1', 'upload', 'secret') and not(xf:alert)]
          | xh:body//xxf:dialog//xf:*[local-name() = ('input', 'textarea', 'select', 'select1', 'upload', 'secret') and not(xf:alert)]">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()"/>
            <xf:alert ref="xxf:r('detail.labels.alert', '|fr-fr-resources|')"/>
        </xsl:copy>
    </xsl:template>

    <!-- Process dynamic LHHA with parameters -->
    <xsl:template
        match="
            xf:label[exists(fr:param)] |
            xf:help [exists(fr:param)] |
            xf:hint [exists(fr:param)] |
            xf:alert[exists(fr:param)]">

        <xsl:copy>
            <xsl:apply-templates select="@*"/>

            <xsl:variable
                name="expr"
                select="
                    concat(
                        'xxf:r(''',
                            frf:controlNameFromId(../@id),
                            '.',
                            local-name(),
                            ''',''fr-form-resources'',',
                            'map:merge((',
                                string-join(
                                    for $p in fr:param
                                    return
                                        concat(
                                            'map:entry(''',
                                                $p/fr:name,
                                                ''',',
                                                if (exists($p/fr:expr)) then
                                                    concat(
                                                        'string((',
                                                        $p/fr:expr,
                                                        ')[1])'
                                                    )
                                                else if (exists($p/fr:controlName)) then
                                                    concat(
                                                        'for $a in fr:control-typed-value(''',
                                                        $p/fr:controlName,
                                                        ''', false()) return if (array:size($a) = 0) then () else array:get($a, 1)'
                                                    )
                                                else
                                                    error(),
                                            ')'
                                        ),
                                    ','
                                ),
                            '))',
                        ')'
                    )
                "/>

            <xsl:attribute
                name="ref"
                select="$expr"/>

        </xsl:copy>
    </xsl:template>

</xsl:stylesheet>
